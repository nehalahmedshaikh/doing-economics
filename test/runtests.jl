using Test
using DataFrames
using DoingEconomics

@testset "DoingEconomics" begin

    @testset "paths" begin
        # Paths must not depend on the caller's working directory, because Quarto
        # renders each .qmd from its own folder.
        @test isabspath(rawpath("01", "x.csv"))
        @test isdir(reporoot("src"))
        @test isfile(reporoot("data", "MANIFEST.toml"))
        @test endswith(replace(rawpath("a.csv"), '\\' => '/'), "data/raw/a.csv")
        @test endswith(replace(procpath("a.csv"), '\\' => '/'), "data/processed/a.csv")
    end

    @testset "palette" begin
        @test length(SERIES) == 8
        @test allunique(SERIES)
        @test all(c -> occursin(r"^#[0-9a-f]{6}$", c), SERIES)
        @test series_color(1) == "#2a78d6"
        @test series_color(8) == SERIES[8]
        # The palette is deliberately not cyclic: a 9th generated hue is
        # indistinguishable from an existing slot under colour-vision deficiency.
        @test_throws ArgumentError series_color(9)
        @test_throws ArgumentError series_color(0)

        @test length(sequential_steps(1)) == 1
        @test sequential_steps(3) == [SEQ_BLUE[1], SEQ_BLUE[7], SEQ_BLUE[13]]
        @test length(sequential_steps(5)) == 5
        @test allunique(sequential_steps(5))
        @test_throws ArgumentError sequential_steps(0)
    end

    @testset "gini" begin
        # Perfect equality, and the limit of perfect concentration.
        @test gini([5, 5, 5, 5]) == 0.0
        @test gini(fill(2.5, 100)) ≈ 0.0 atol = 1e-12
        @test gini([0, 0, 0, 1]) ≈ 0.75
        @test gini([0, 0, 0, 0, 1]) ≈ 0.8

        # Weighted and unweighted forms must agree, or weighted results computed
        # from a decile table would not be comparable with unweighted ones.
        @test gini([1, 2, 3]) ≈ gini([1, 2, 3]; weights = [1, 1, 1])
        @test gini([1, 1, 2, 2]) ≈ gini([1, 2]; weights = [2, 2])
        @test gini([1, 1, 2, 2]) ≈ 1 / 6

        # Order must not matter.
        @test gini([3, 1, 2]) ≈ gini([1, 2, 3])

        @test gini([1, missing, 2, 3]) ≈ gini([1, 2, 3])
        @test isnan(gini(Float64[]))
        @test gini([0, 0, 0]) == 0.0

        @test_throws DimensionMismatch gini([1, 2]; weights = [1])
        @test_throws ArgumentError gini([1, 2]; weights = [-1, 1])
    end

    @testset "lorenz" begin
        L = lorenz([1, 1, 1, 1])
        @test L.population ≈ [0.0, 0.25, 0.5, 0.75, 1.0]
        # Under equality the curve is the 45-degree line.
        @test L.share ≈ L.population

        U = lorenz([0, 0, 0, 1])
        @test U.share ≈ [0.0, 0.0, 0.0, 0.0, 1.0]

        # Both axes are cumulative shares: start at 0, end at 1, never decrease.
        for x in ([3, 1, 4, 1, 5, 9, 2, 6], [10, 20, 30])
            C = lorenz(x)
            @test first(C.population) == 0.0 && last(C.population) ≈ 1.0
            @test first(C.share) == 0.0 && last(C.share) ≈ 1.0
            @test issorted(C.share)
            @test issorted(C.population)
            # The curve can never sit above the line of equality.
            @test all(C.share .<= C.population .+ 1e-12)
        end

        @test lorenz(Float64[]).population == Float64[]
        @test_throws ArgumentError lorenz([0, 0, 0])
    end

    @testset "cumulative_share and decile_shares" begin
        @test cumulative_share([1, 1, 1, 1], 0.5) ≈ 0.5
        @test cumulative_share([1, 1, 1, 1], 0.0) == 0.0
        @test cumulative_share([1, 1, 1, 1], 1.0) ≈ 1.0
        @test cumulative_share([0, 0, 1, 1], 0.5) ≈ 0.0
        @test_throws ArgumentError cumulative_share([1, 2], 1.5)

        d = decile_shares(1:100)
        @test length(d) == 10
        @test sum(d) ≈ 1.0
        # A rising distribution means each decile holds more than the one below it.
        @test issorted(d)

        @test decile_shares([1, 1, 1, 1, 1]; n = 5) ≈ fill(0.2, 5)
        @test sum(decile_shares(1:50; n = 5)) ≈ 1.0
        @test_throws ArgumentError decile_shares([1, 2]; n = 0)

        # Weights are just a compressed way of writing repeated observations.
        @test decile_shares([1, 2]; weights = [5, 5], n = 2) ≈
              decile_shares([1, 1, 1, 1, 1, 2, 2, 2, 2, 2]; n = 2)
    end

    @testset "freqtable_binned" begin
        # Defaults follow R's `hist`: right-closed bins, lowest value included.
        t = freqtable_binned([0, 1, 2, 3]; breaks = 0:1:3)
        @test t isa DataFrame
        @test names(t) == ["lower", "upper", "bin", "count", "proportion"]
        @test t.count == [2, 1, 1]          # 0 and 1 -> (0,1]; 2 -> (1,2]; 3 -> (2,3]
        @test t.bin == ["(0, 1]", "(1, 2]", "(2, 3]"]
        @test sum(t.proportion) ≈ 1.0

        # Left-closed drops the top edge instead of the bottom one.
        t2 = freqtable_binned([0, 1, 2, 3]; breaks = 0:1:3, closed = :left)
        @test t2.count == [1, 1, 1]
        @test t2.bin == ["[0, 1)", "[1, 2)", "[2, 3)"]

        t3 = freqtable_binned([0, 1, 2, 3]; breaks = 0:1:3, include_lowest = false)
        @test t3.count == [1, 1, 1]

        @test freqtable_binned([1, missing, 2]; breaks = 0:1:3).count == [1, 1, 0]

        e = freqtable_binned(Float64[]; breaks = 0:1:2)
        @test e.count == [0, 0]
        @test all(iszero, e.proportion)

        @test_throws ArgumentError freqtable_binned([1]; breaks = 0:1:2, closed = :middle)
        @test_throws ArgumentError freqtable_binned([1]; breaks = [1.0])
        @test_throws ArgumentError freqtable_binned([1]; breaks = [3.0, 1.0, 2.0])
    end

    @testset "series transforms" begin
        pc = pct_change([100, 110, 99])
        @test ismissing(pc[1])
        @test pc[2] ≈ 10.0
        @test pc[3] ≈ -10.0

        @test ismissing(pct_change([0, 5])[2])            # zero base
        @test ismissing(pct_change([1, missing, 3])[2])
        @test ismissing(pct_change([1, missing, 3])[3])
        @test isempty(pct_change(Float64[]))

        @test geometric_mean([1, 4, 16]) ≈ 4.0
        @test geometric_mean([0.5, 0.5]) ≈ 0.5
        @test geometric_mean([7]) ≈ 7.0
        # A zero in any dimension zeroes the whole index - the property that makes it
        # the right mean for the HDI.
        @test geometric_mean([0.9, 0.9, 0.0]) == 0.0
        # Never above the arithmetic mean, equal only when all values match.
        @test geometric_mean([1, 100]) ≈ 10.0        # arithmetic mean is 50.5
        @test geometric_mean([3, 3, 3]) ≈ 3.0        # equal values: the two agree
        @test geometric_mean([2, missing, 8]) ≈ 4.0
        @test isnan(geometric_mean(Float64[]))
        # Log-space summation, so a long vector cannot overflow the product.
        @test geometric_mean(fill(1e200, 500)) ≈ 1e200 rtol = 1e-8
        @test_throws ArgumentError geometric_mean([-1, 4])

        @test index_to([50, 100, 150], 1) ≈ [100.0, 200.0, 300.0]
        @test index_to([50, 100, 150], 2) ≈ [50.0, 100.0, 150.0]
        @test index_to([2, 4], 1; base = 1) ≈ [1.0, 2.0]
        @test ismissing(index_to([1, missing, 3], 1)[2])
        @test_throws ArgumentError index_to([0, 1], 1)
        @test_throws ArgumentError index_to([missing, 1], 1)
        @test_throws BoundsError index_to([1, 2], 5)
    end

    @testset "checksums" begin
        # SHA-256 of the empty string, as a fixed reference point.
        mktemp() do path, io
            close(io)
            @test sha256_file(path) ==
                  "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        end
    end

    @testset "show_all" begin
        # Quarto's engine displays results with `:limit => true`, which makes DataFrames
        # elide the middle of a long table. Anything cited in prose has to be visible.
        long = DataFrame(i = 1:46, x = collect(1.0:46))
        render(x; limit) =
            sprint((io, v) -> show(IOContext(io, :limit => limit),
                                   MIME("text/html"), v), x)

        @test occursin(">46<", render(long; limit = false))
        @test !occursin(">30<", render(long; limit = true))          # the bug
        @test occursin(">30<", render(show_all(long); limit = true)) # the fix
        @test occursin(">46<", render(show_all(long); limit = true))

        # Every row present, and the elision marker gone.
        html = render(show_all(long); limit = true)
        @test !occursin("⋮", html)
        @test all(occursin(">$i<", html) for i in 1:46)

        # Plain-text display is forwarded the same way.
        @test occursin("46", sprint((io, v) -> show(IOContext(io, :limit => true),
                                                    MIME("text/plain"), v),
                                    show_all(long)))

        # No generic `show(::IO, ::MIME, ::AllRows)`. Quarto picks an output format by
        # attempting `show` rather than by asking `showable`, so a catch-all method
        # advertises formats DataFrames cannot render and the render fails mid-cell.
        T = typeof(show_all(long))
        @test hasmethod(show, Tuple{IO, MIME"text/html", T})
        @test hasmethod(show, Tuple{IO, MIME"text/plain", T})
        @test !hasmethod(show, Tuple{IO, MIME"text/markdown", T})
        @test !hasmethod(show, Tuple{IO, MIME"image/png", T})
        @test !showable(MIME("text/markdown"), show_all(long))
    end

    @testset "theme" begin
        th = doingecon_theme()
        @test th.backgroundcolor[] == SURFACE
        @test th.Axis.xgridstyle[] === :solid   # gridlines are never dashed
        @test th.Lines.linewidth[] == 2
        @test th.Legend.framevisible[] == false
    end

end
