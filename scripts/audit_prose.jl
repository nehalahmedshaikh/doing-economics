#!/usr/bin/env julia
"""
Check that every number asserted in a project's prose appears in that project's
*computed* output.

The failure this exists to catch: a figure typed into a sentence from memory or from an
earlier data vintage, which no amount of re-reading reliably finds. It has happened twice
in this repository — a work-ethic mean and a set of index numbers — and both times the
number was wrong in a way that changed what the paragraph claimed.

For each rendered project the script collects

  * **prose numbers** from the `.qmd`, with code cells, inline code and math removed, and
  * **computed numbers** from the rendered HTML: every non-source `<pre>` block, every
    DataFrame table, and every `<text>` element in the figure SVGs,

then reports prose numbers that no computed value rounds to at the precision the prose
states, alongside the nearest computed value so a typo is distinguishable from rounding.

Run it after rendering:

    julia --project=. scripts/audit_prose.jl
    julia --project=. scripts/audit_prose.jl 08-unemployment-cost

**This is a report, not a gate.** Legitimate prose numbers do not appear in any output:
section cross-references ("Part 8.2"), statistical constants (1.96), values explicitly
attributed to the book, external facts, and arithmetic derived from two printed figures.
Roughly one flag in six has been a real error. Every flag still has to be read — the
script narrows where to look, it does not decide.

Where a number genuinely depends on the data vintage, the durable fix is an inline
expression in the prose rather than a typed literal, so the sentence cannot go stale.
"""

const REPO = normpath(joinpath(@__DIR__, ".."))

# A number, optionally negative (ASCII hyphen or Unicode minus), with optional thousands
# separators and decimals. Not preceded or followed by a word character, so version
# strings and identifiers are skipped.
const NUMBER = r"(?<![\w.])(-|−)?\d[\d,]*(?:\.\d+)?(?![\w])"

"""Every number in `text` as `(value, literal, offset)`."""
function numbers(text::AbstractString)
    found = Tuple{Float64, String, Int}[]
    for m in eachmatch(NUMBER, text)
        cleaned = replace(m.match, "," => "", "−" => "-")
        value = tryparse(Float64, cleaned)
        value === nothing || push!(found, (value, String(m.match), m.offset))
    end
    return found
end

"""The `.qmd` with everything that is not prose removed."""
function prose(qmd::AbstractString)
    text = read(qmd, String)
    text = replace(text, r"^---.*?\n---\n"s => "")          # YAML front matter
    text = replace(text, r"```\{julia\}.*?\n```"s => " ")   # executed cells
    text = replace(text, r"```.*?\n```"s => " ")            # static code blocks
    text = replace(text, r"`\{julia\}[^`]*`" => " ")        # inline expressions
    text = replace(text, r"`[^`\n]*`" => " ")               # inline code
    text = replace(text, r"\$\$.*?\$\$"s => " ")            # display math
    text = replace(text, r"\$[^\$\n]*\$" => " ")            # inline math
    text = replace(text, r"\]\([^)]*\)" => "] ")            # link targets
    text = replace(text, r"\{#[^}]*\}" => " ")              # section anchors
    return text
end

strip_tags(s) = replace(s, r"<[^>]+>"s => " ")

function unescape_entities(s)
    for (from, to) in ("&amp;" => "&", "&lt;" => "<", "&gt;" => ">",
                       "&quot;" => "\"", "&#39;" => "'", "&nbsp;" => " ")
        s = replace(s, from => to)
    end
    return s
end

"""Every number the rendered page actually computed."""
function computed(page_dir::AbstractString)
    values = Set{Float64}()
    index = joinpath(page_dir, "index.html")
    if isfile(index)
        html = read(index, String)
        # Drop the echoed source so literals in the code are not mistaken for results.
        html = replace(html, r"<pre class=\"sourceCode.*?</pre>"s => " ")
        blocks = [m.match for m in eachmatch(r"<pre>.*?</pre>"s, html)]
        append!(blocks, (m.match for m in eachmatch(r"<table class=\"data-frame.*?</table>"s,
                                                    html)))
        for block in blocks, (v, _, _) in numbers(unescape_entities(strip_tags(block)))
            push!(values, v)
        end
    end
    figures = joinpath(page_dir, "index_files", "figure-html")
    if isdir(figures)
        for file in readdir(figures; join = true)
            endswith(file, ".svg") || continue
            svg = read(file, String)
            for m in eachmatch(r"<text[^>]*>(.*?)</text>"s, svg)
                for (v, _, _) in numbers(unescape_entities(strip_tags(m.captures[1])))
                    push!(values, v)
                end
            end
        end
    end
    return values
end

"""Does any computed value round to `value` at the precision `literal` states?"""
function is_supported(value, literal, values)
    value in values && return true
    decimals = contains(literal, '.') ? length(split(literal, '.')[2]) : 0
    tol = 0.5 * 10.0^(-decimals)       # tolerance, not `round`: avoids float-repr misses
    for v in values
        abs(v - value) <= tol && return true
        # Prose often quotes a percentage of something reported as a fraction.
        iszero(v) && continue
        (abs(v * 100 - value) <= tol || abs(v / 100 - value) <= tol) && return true
        # A magnitude cited for a signed result, e.g. an elasticity printed as -1.22.
        abs(abs(v) - abs(value)) <= tol && return true
    end
    return false
end

"""Closest computed value in relative terms, to separate a typo from a rounding choice."""
function nearest(value, values)
    isempty(values) && return (nothing, nothing)
    scale = max(abs(value), 1e-9)
    best = argmin(v -> abs(v - value) / scale, values)
    return (best, abs(best - value) / scale)
end

"""Numbers that carry no claim about the data and are never worth flagging."""
function uninteresting(value, literal)
    integer = !contains(literal, '.')
    integer && 1700 <= value <= 2100 && return true    # years
    integer && abs(value) <= 12 && return true         # counts, list items, scale points
    literal in ("0.05", "1.96", "0.95", "100") && return true   # conventional constants
    return false
end

"""
Rendered tables that lost their middle row.

Unlike the prose check this has no false positives: a `⋮` inside a DataFrame table on a web
page is always a bug, so this one is worth failing a build over. Quarto's engine displays
results with `:limit => true`, which makes DataFrames elide past about 26 rows — see
`show_all` in `DoingEconomics`.
"""
function truncated_tables()
    offenders = Tuple{String, Int}[]
    for name in sort(readdir(joinpath(REPO, "projects")))
        index = joinpath(REPO, "docs", "projects", name, "index.html")
        isfile(index) || continue
        html = read(index, String)
        tables = [m.match for m in eachmatch(r"<table class=\"data-frame.*?</table>"s, html)]
        count = sum(contains(t, "⋮") for t in tables; init = 0)
        count > 0 && push!(offenders, (name, count))
    end
    return offenders
end

function audit(selection = String[])
    projects = sort(readdir(joinpath(REPO, "projects")))
    isempty(selection) || (projects = filter(in(selection), projects))
    total = flagged = 0

    for name in projects
        qmd = joinpath(REPO, "projects", name, "index.qmd")
        isfile(qmd) || continue
        values = computed(joinpath(REPO, "docs", "projects", name))
        if isempty(values)
            println("\n$name — no rendered output found; render before auditing")
            continue
        end

        text = prose(qmd)
        hits = String[]
        for (value, literal, offset) in numbers(text)
            uninteresting(value, literal) && continue
            total += 1
            is_supported(value, literal, values) && continue
            near, rel = nearest(value, values)
            # Bounds in named variables: Julia does not allow a line break after the `:`
            # of a range expression.
            from = max(firstindex(text), prevind(text, offset, min(offset - 1, 85)))
            to = min(lastindex(text), nextind(text, offset, 85))
            context = replace(strip(text[from:to]), r"\s+" => " ")
            note = rel !== nothing && rel <= 0.02 ? "  [close — check rounding]" : ""
            push!(hits, "  $(lpad(literal, 11))  nearest computed " *
                        "$(rpad(repr(near), 22))$note\n      …$context…")
        end
        flagged += length(hits)
        println("\n", "="^96)
        println("$name — $(length(values)) computed values, $(length(hits)) unsupported")
        foreach(println, hits)
    end

    println("\n", "="^96)
    println("checked $total prose numbers, $flagged unsupported")
    println("Flags are candidates, not errors: cross-references, constants, " *
            "book-attributed values\nand derived arithmetic all land here. Read each one.")

    offenders = truncated_tables()
    if isempty(offenders)
        println("\nno truncated tables")
    else
        println("\nTRUNCATED TABLES — rows hidden behind a `⋮`; wrap them in `show_all`:")
        for (name, count) in offenders
            println("  $name: $count table$(count == 1 ? "" : "s")")
        end
    end
    return (; prose_flags = flagged, truncated = length(offenders))
end

# Block form, not `... == @__FILE__ && audit(ARGS)`: the macro would swallow the
# `&& audit(ARGS)` as its own arguments.
if abspath(PROGRAM_FILE) == @__FILE__
    result = audit(ARGS)
    # Exit non-zero on truncation only. Prose flags need a human read and would fail
    # every build; a hidden table row is unambiguous.
    exit(result.truncated == 0 ? 0 : 1)
end
