"""
    DoingEconomics

Shared helpers for the *Doing Economics* empirical projects in Julia.

Three groups of things live here:

  * **Paths** — [`rawpath`](@ref), [`procpath`](@ref) resolve data locations relative to
    the repository root, so a `.qmd` renders identically from any working directory.
  * **Chart theme** — [`use_doingecon_theme!`](@ref) applies one Makie theme across every
    figure in the book, plus the fixed categorical palette in [`SERIES`](@ref).
  * **Statistics** — the measures the book builds by hand in more than one project:
    [`gini`](@ref), [`lorenz`](@ref), [`decile_shares`](@ref), [`freqtable_binned`](@ref),
    [`pct_change`](@ref), [`index_to`](@ref).

Anything used by exactly one project stays in that project's `.qmd`; this module is only
for what genuinely repeats.
"""
module DoingEconomics

using Statistics: mean
using StatsBase: Histogram, fit
using DataFrames: DataFrame
using Downloads: download
using SHA: sha256
using Printf: @sprintf
using Makie: Theme, set_theme!

export reporoot, rawpath, procpath, projectpath
export SURFACE, INK, INK_SECONDARY, MUTED, GRIDLINE, BASELINE
export SERIES, SEQ_BLUE, series_color, sequential_steps
export doingecon_theme, use_doingecon_theme!
export gini, lorenz, cumulative_share, decile_shares
export freqtable_binned, pct_change, index_to
export sha256_file, fetch_verified

# ── paths ─────────────────────────────────────────────────────────────────────
# `@__DIR__` is `<repo>/src`, so the repo root is one level up. This is resolved at
# load time and does not depend on the caller's working directory, which matters
# because Quarto renders each .qmd with its own directory as `pwd()`.
const REPO_ROOT = normpath(joinpath(@__DIR__, ".."))

"""    reporoot(parts...)

Absolute path inside the repository, e.g. `reporoot("data", "MANIFEST.toml")`.
"""
reporoot(parts::AbstractString...) = normpath(joinpath(REPO_ROOT, parts...))

"""    rawpath(parts...)

Absolute path inside `data/raw/` — the untouched downloads described by
`data/MANIFEST.toml`. Not committed to git.
"""
rawpath(parts::AbstractString...) = reporoot("data", "raw", parts...)

"""    procpath(parts...)

Absolute path inside `data/processed/` — derived, tidied files written by project code.
Not committed to git; always reproducible from `data/raw/`.
"""
procpath(parts::AbstractString...) = reporoot("data", "processed", parts...)

"""    projectpath(parts...)

Absolute path inside `projects/`.
"""
projectpath(parts::AbstractString...) = reporoot("projects", parts...)

# ── palette ───────────────────────────────────────────────────────────────────
# Light-mode values from the project's validated palette. The site renders light-only
# so that these static figures always sit on the surface they were designed against;
# a light/dark toggle would leave the PNGs stranded on the wrong background.

const SURFACE       = "#fcfcfb"  # chart surface
const INK           = "#0b0b0b"  # primary text (titles)
const INK_SECONDARY = "#52514e"  # axis labels, legend text
const MUTED         = "#898781"  # tick labels
const GRIDLINE      = "#e1e0d9"  # hairline grid
const BASELINE      = "#c3c2b7"  # axis rule

"""
    SERIES

The eight categorical slots, in fixed order. Order is the colourblind-safety
mechanism, not a cosmetic choice — it was chosen so that every *adjacent* pair clears
the CVD and normal-vision separation floors. Assign slots in order and never cycle:
see [`series_color`](@ref).

For chart forms where any two series can end up side by side (scatter, bubble),
only the **first three** slots are safe; past that, fold the tail into "Other" or
facet into small multiples.
"""
const SERIES = [
    "#2a78d6",  # 1 blue
    "#eb6834",  # 2 orange
    "#1baf7a",  # 3 aqua
    "#eda100",  # 4 yellow
    "#e87ba4",  # 5 magenta
    "#008300",  # 6 green
    "#4a3aa7",  # 7 violet
    "#e34948",  # 8 red
]

"""
    SEQ_BLUE

Single-hue blue ramp, light → dark, for encoding *magnitude* (heatmaps, ordered bins).
Never use it on unordered categories — that double-encodes bar length as hue.
"""
const SEQ_BLUE = [
    "#cde2fb", "#b7d3f6", "#9ec5f4", "#86b6ef", "#6da7ec", "#5598e7",
    "#3987e5", "#2a78d6", "#256abf", "#1c5cab", "#184f95", "#104281", "#0d366b",
]

"""
    series_color(i)

The `i`-th categorical slot. Throws past slot 8 rather than wrapping around: a ninth
generated hue is indistinguishable from an existing slot under colour-vision
deficiency, so the palette is deliberately not cyclic.
"""
function series_color(i::Integer)
    if !(1 ≤ i ≤ length(SERIES))
        throw(ArgumentError(
            "categorical slot $i is out of range: the palette has $(length(SERIES)) " *
            "fixed slots and is never cycled. Fold the tail into \"Other\", facet " *
            "into small multiples, or encode the extra dimension some other way."))
    end
    return SERIES[i]
end

"""
    sequential_steps(n; ramp = SEQ_BLUE)

`n` evenly spaced steps from a single-hue ramp, light → dark, for `n` ordered bins.
"""
function sequential_steps(n::Integer; ramp = SEQ_BLUE)
    n ≥ 1 || throw(ArgumentError("need at least one step, got $n"))
    n == 1 && return [ramp[cld(length(ramp), 2)]]
    idx = round.(Int, range(1, length(ramp); length = n))
    return ramp[idx]
end

# ── chart theme ───────────────────────────────────────────────────────────────

"""
    doingecon_theme()

The Makie `Theme` shared by every figure in the book: hairline solid gridlines, no
tick marks, only a bottom spine, recessive greys for chrome, and the fixed
categorical palette.

Fonts are left at Makie's bundled sans (a Helvetica clone) rather than a system face
so that figures render identically on Windows and in CI.
"""
function doingecon_theme()
    return Theme(
        backgroundcolor = SURFACE,
        figure_padding = 16,
        fontsize = 13,
        palette = (; color = SERIES, patchcolor = SERIES),
        Axis = (
            backgroundcolor = SURFACE,
            # Hairline, solid, one step off the surface. Never dashed.
            xgridcolor = GRIDLINE, ygridcolor = GRIDLINE,
            xgridwidth = 1, ygridwidth = 1,
            xgridstyle = :solid, ygridstyle = :solid,
            xminorgridvisible = false, yminorgridvisible = false,
            # A single baseline rule; the other three spines are chrome we don't need.
            leftspinevisible = false, rightspinevisible = false, topspinevisible = false,
            bottomspinevisible = true, bottomspinecolor = BASELINE,
            xticksvisible = false, yticksvisible = false,
            xticklabelcolor = MUTED, yticklabelcolor = MUTED,
            xticklabelsize = 11, yticklabelsize = 11,
            xlabelcolor = INK_SECONDARY, ylabelcolor = INK_SECONDARY,
            xlabelsize = 12, ylabelsize = 12,
            titlecolor = INK, titlesize = 15, titlealign = :left, titlegap = 10,
            subtitlecolor = INK_SECONDARY, subtitlesize = 12,
        ),
        Lines = (linewidth = 2, joinstyle = :round, linecap = :round),
        # A 2px ring in the surface colour keeps overlapping dots legible.
        Scatter = (markersize = 9, strokewidth = 2, strokecolor = SURFACE),
        # `gap` is the surface separation between adjacent bars; no stroke around marks.
        BarPlot = (strokewidth = 0, gap = 0.15),
        Hist = (strokewidth = 0, gap = 0.15),
        Legend = (
            framevisible = false,
            labelcolor = INK_SECONDARY, labelsize = 12,
            titlecolor = INK_SECONDARY, titlesize = 12,
            patchsize = (12, 12), rowgap = 4, padding = (8, 8, 8, 8),
        ),
        Label = (color = INK_SECONDARY,),
        Text = (color = INK_SECONDARY,),
    )
end

"""
    use_doingecon_theme!()

Apply [`doingecon_theme`](@ref) globally. Call once in the setup cell of each project.
"""
use_doingecon_theme!() = set_theme!(doingecon_theme())

# ── distribution measures ─────────────────────────────────────────────────────

"""
    _clean_sorted(x, weights) -> (values, weights)

Drop pairs where either side is `missing`, validate the weights, and sort ascending by
value. Shared by [`gini`](@ref) and [`lorenz`](@ref) so the two can never disagree
about how they treat the input.
"""
function _clean_sorted(x, weights)
    xv = collect(x)
    wv = weights === nothing ? ones(Float64, length(xv)) : collect(weights)
    if length(xv) != length(wv)
        throw(DimensionMismatch(
            "got $(length(xv)) values but $(length(wv)) weights"))
    end
    keep = [!ismissing(a) && !ismissing(b) for (a, b) in zip(xv, wv)]
    vals = Float64[xv[i] for i in eachindex(xv) if keep[i]]
    wts  = Float64[wv[i] for i in eachindex(wv) if keep[i]]
    any(<(0), wts) && throw(ArgumentError("weights must be non-negative"))
    if any(<(0), vals)
        @warn "negative values present — the Lorenz curve and Gini coefficient " *
              "are not well defined for negative amounts"
    end
    p = sortperm(vals)
    return vals[p], wts[p]
end

"""
    lorenz(x; weights = nothing)

Lorenz curve of `x`: the cumulative share of the population against the cumulative
share of the total. Returns a `NamedTuple` of `population` and `share` vectors with the
origin `(0, 0)` prepended, so it plots directly against the 45° line of equality.

`weights` lets a single row stand for many people (survey weights, or a decile table
where each row is a tenth of the population).

```jldoctest
julia> L = lorenz([1, 1, 1, 1]);

julia> L.share ≈ [0.0, 0.25, 0.5, 0.75, 1.0]
true
```
"""
function lorenz(x; weights = nothing)
    vals, wts = _clean_sorted(x, weights)
    isempty(vals) && return (population = Float64[], share = Float64[])
    cum_w = cumsum(wts)
    cum_v = cumsum(wts .* vals)
    total_w, total_v = cum_w[end], cum_v[end]
    total_w == 0 && throw(ArgumentError("lorenz: weights sum to zero"))
    total_v == 0 && throw(ArgumentError("lorenz: values sum to zero"))
    return (population = vcat(0.0, cum_w ./ total_w),
            share      = vcat(0.0, cum_v ./ total_v))
end

"""
    gini(x; weights = nothing)

Gini coefficient of `x` — twice the area between the Lorenz curve and the line of
equality. `0` means everyone holds the same amount; it approaches `1` as one unit holds
everything.

This is the *population* (biased) form, the one the book computes. With equal weights it
agrees exactly with the unweighted formula, so weighted and unweighted results are
comparable.

```jldoctest
julia> gini([5, 5, 5, 5])
0.0

julia> round(gini([0, 0, 0, 1]); digits = 2)
0.75
```
"""
function gini(x; weights = nothing)
    vals, wts = _clean_sorted(x, weights)
    isempty(vals) && return NaN
    cum_v = cumsum(wts .* vals)
    total_v = cum_v[end]
    total_w = sum(wts)
    total_w == 0 && throw(ArgumentError("gini: weights sum to zero"))
    total_v == 0 && return 0.0
    prev = vcat(0.0, cum_v[1:end - 1])
    return 1 - sum(wts .* (prev .+ cum_v)) / (total_w * total_v)
end

"""
    _interp(xs, ys, q)

Linear interpolation of `ys` at `q`, where `xs` is sorted ascending. Used to read the
Lorenz curve at population shares that fall between observations.
"""
function _interp(xs::AbstractVector, ys::AbstractVector, q::Real)
    q ≤ first(xs) && return float(first(ys))
    q ≥ last(xs) && return float(last(ys))
    i = searchsortedfirst(xs, q)
    x0, x1 = xs[i - 1], xs[i]
    y0, y1 = ys[i - 1], ys[i]
    x1 == x0 && return float(y1)
    return float(y0 + (y1 - y0) * (q - x0) / (x1 - x0))
end

"""
    cumulative_share(x, q; weights = nothing)

Share of the total held by the poorest `q` fraction of the population, read off the
Lorenz curve. `cumulative_share(income, 0.5)` is the share held by the bottom half.
"""
function cumulative_share(x, q::Real; weights = nothing)
    0 ≤ q ≤ 1 || throw(ArgumentError("q must be in [0, 1], got $q"))
    L = lorenz(x; weights)
    isempty(L.population) && return NaN
    return _interp(L.population, L.share, q)
end

"""
    decile_shares(x; weights = nothing, n = 10)

Share of the total held by each of `n` equal-sized population groups, poorest first.
Sums to 1. `n = 10` gives deciles, `n = 5` quintiles.

Computed by differencing the Lorenz curve, so it is exact for pre-grouped data and
handles weights without needing weighted quantiles.
"""
function decile_shares(x; weights = nothing, n::Integer = 10)
    n ≥ 1 || throw(ArgumentError("need at least one group, got $n"))
    L = lorenz(x; weights)
    isempty(L.population) && return fill(NaN, n)
    cuts = [_interp(L.population, L.share, q) for q in range(0, 1; length = n + 1)]
    return diff(cuts)
end

# ── frequency tables ──────────────────────────────────────────────────────────

function _bin_labels(lower, upper, closed::Symbol)
    fmt(v) = isinteger(v) ? string(Int(v)) : @sprintf("%.2f", v)
    return closed === :right ?
        ["(" * fmt(l) * ", " * fmt(u) * "]" for (l, u) in zip(lower, upper)] :
        ["[" * fmt(l) * ", " * fmt(u) * ")" for (l, u) in zip(lower, upper)]
end

"""
    freqtable_binned(x; breaks, closed = :right, include_lowest = true)

Frequency table of `x` over the intervals given by `breaks`, returned as a `DataFrame`
with `lower`, `upper`, `bin`, `count`, and `proportion` columns.

The defaults match R's `hist`, which the book's walk-throughs use: intervals are
right-closed `(a, b]`, and `include_lowest` folds values sitting exactly on the first
break into the first bin. Pass `closed = :left` for `[a, b)` intervals instead.

Values outside `breaks` are not counted; the function warns when it drops any, because
a silently truncated histogram is the kind of thing that quietly changes an answer.
"""
function freqtable_binned(x; breaks, closed::Symbol = :right, include_lowest::Bool = true)
    closed in (:right, :left) ||
        throw(ArgumentError("closed must be :right or :left, got :$closed"))
    edges = Float64.(collect(breaks))
    length(edges) ≥ 2 || throw(ArgumentError("breaks needs at least two edges"))
    issorted(edges) || throw(ArgumentError("breaks must be sorted ascending"))

    vals = Float64[v for v in skipmissing(x)]
    lo, hi = first(edges), last(edges)

    # Count out-of-range values before binning, treating the boundary the same way the
    # chosen interval convention does.
    outside = count(v -> v < lo || v > hi, vals)
    if closed === :right && !include_lowest
        outside += count(==(lo), vals)
    elseif closed === :left
        outside += count(==(hi), vals)
    end
    outside > 0 && @warn "$outside value(s) fall outside `breaks` and are not counted"

    inrange = filter(v -> lo ≤ v ≤ hi, vals)
    h = fit(Histogram, inrange, edges; closed = closed)
    counts = collect(h.weights)

    # StatsBase drops values equal to the outer edge of the open side; R's
    # `include.lowest = TRUE` keeps them, so put them back.
    if closed === :right && include_lowest
        counts[1] += count(==(lo), inrange)
    end

    total = sum(counts)
    return DataFrame(
        lower = edges[1:end - 1],
        upper = edges[2:end],
        bin = _bin_labels(edges[1:end - 1], edges[2:end], closed),
        count = counts,
        proportion = total == 0 ? zeros(length(counts)) : counts ./ total,
    )
end

# ── series transforms ─────────────────────────────────────────────────────────

"""
    pct_change(x)

Period-on-period percentage change, `missing` for the first element and wherever the
change cannot be computed (a `missing` neighbour, or a zero base).
"""
function pct_change(x)
    v = collect(x)
    out = Vector{Union{Missing, Float64}}(missing, length(v))
    for i in 2:length(v)
        prev, cur = v[i - 1], v[i]
        (ismissing(prev) || ismissing(cur) || iszero(prev)) && continue
        out[i] = 100 * (cur - prev) / prev
    end
    return out
end

"""
    index_to(x, base_index; base = 100)

Rescale `x` so that `x[base_index]` equals `base`. This is how two series measured in
different units get compared on one axis — the honest alternative to a second y-scale.
"""
function index_to(x, base_index::Integer; base::Real = 100)
    v = collect(x)
    checkbounds(v, base_index)
    anchor = v[base_index]
    ismissing(anchor) && throw(ArgumentError("base value at index $base_index is missing"))
    iszero(anchor) && throw(ArgumentError("base value at index $base_index is zero"))
    return [ismissing(vi) ? missing : base * vi / anchor for vi in v]
end

# ── data fetching ─────────────────────────────────────────────────────────────

"""    sha256_file(path)

Lowercase hex SHA-256 of a file's contents.
"""
sha256_file(path::AbstractString) = bytes2hex(open(sha256, path))

"""
    fetch_verified(url, dest; sha256 = nothing, force = false)

Download `url` to `dest`, creating parent directories as needed, and verify the
checksum. Returns `dest`.

An existing file with a matching checksum is left alone, so re-running the fetch script
is cheap. A checksum mismatch on a *fresh* download is an error — the upstream file
changed, and the manifest needs updating deliberately rather than silently.

Pass `sha256 = nothing` for sources that legitimately change over time (NASA GISS is
reissued monthly); the download then happens unverified and warns.
"""
function fetch_verified(url::AbstractString, dest::AbstractString;
                        sha256::Union{Nothing, AbstractString} = nothing,
                        force::Bool = false)
    mkpath(dirname(dest))

    if isfile(dest) && !force
        if sha256 === nothing
            @info "already present (unverified, source is not stable)" dest
            return dest
        elseif sha256_file(dest) == lowercase(sha256)
            @info "already present and verified" dest
            return dest
        else
            @warn "checksum mismatch on the local copy — re-downloading" dest
        end
    end

    @info "downloading" url dest
    tmp = dest * ".part"
    try
        download(url, tmp)
    catch err
        isfile(tmp) && rm(tmp; force = true)
        rethrow(err)
    end

    if sha256 !== nothing
        got = sha256_file(tmp)
        if got != lowercase(sha256)
            rm(tmp; force = true)
            error("""
                  checksum mismatch for $url
                    expected: $(lowercase(sha256))
                    got:      $got
                  The upstream file has changed. Check the source, then update the
                  sha256 in data/MANIFEST.toml deliberately.
                  """)
        end
    else
        @warn "no checksum recorded for this source; downloaded without verification" url
    end

    mv(tmp, dest; force = true)
    return dest
end

end # module
