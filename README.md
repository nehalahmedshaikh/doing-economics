# Doing Economics in Julia

Julia implementations of the fourteen empirical projects in CORE Econ's
[*Doing Economics*](https://books.core-econ.org/doing-economics/index.html) — applied economics
built on real datasets: climate records, experimental results, household surveys, bank balance
sheets. The book ships walk-throughs in Excel, R, Google Sheets, and Python, but not Julia.

**📊 [Read the projects →](https://nehalahmedshaikh.github.io/doing-economics)**

## What this is

Each project follows the book's structure: every Part, every numbered question, with Julia code
and a written answer. Results are checked against the published solutions and differences are
explained.

Two deliberate departures:

- **The analysis follows the book; some charts don't.** Project 1's walk-through builds a
  dual-axis temperature/CO₂ chart. Where two y-scales line up is an arbitrary choice, so
  sliding one changes how strongly the series appear to track with no number changing. Here
  that becomes two panels plus the correlation coefficient, flagged in a note on the page.
- **Live data moves.** NASA GISS reissues its temperature record monthly, revising the whole
  series slightly. Figures rendered today differ from the published solutions in the last
  decimal. Every page states its data vintage; `data/MANIFEST.toml` records the checksum.

## Progress

| # | Project | Status |
|---|---------|--------|
| 1 | [Measuring climate change](https://nehalahmedshaikh.github.io/doing-economics/projects/01-measuring-climate-change/) | ✅ Done |
| 2 | [Collecting and analysing data from experiments](https://nehalahmedshaikh.github.io/doing-economics/projects/02-data-from-experiments/) | ✅ Done |
| 3 | [Measuring the effect of a sugar tax](https://nehalahmedshaikh.github.io/doing-economics/projects/03-sugar-tax/) | ✅ Done |
| 4 | [Measuring wellbeing](https://nehalahmedshaikh.github.io/doing-economics/projects/04-measuring-wellbeing/) | ✅ Done |
| 5 | [Measuring inequality: Lorenz curves and Gini coefficients](https://nehalahmedshaikh.github.io/doing-economics/projects/05-measuring-inequality/) | ✅ Done |
| 6 | [Measuring management practices](https://nehalahmedshaikh.github.io/doing-economics/projects/06-management-practices/) | ✅ Done |
| 7 | [Supply and demand](https://nehalahmedshaikh.github.io/doing-economics/projects/07-supply-and-demand/) | ✅ Done |
| 8 | Measuring the non-monetary cost of unemployment | Planned |
| 9 | Credit-excluded households in a developing country | Planned |
| 10 | Characteristics of banking systems around the world | Planned |
| 11 | Measuring willingness to pay for climate change mitigation | Planned |
| 12 | Government policies and popularity: Hong Kong cash handout | Planned |
| 13 | Extra 1: Female labour supply and the macroeconomy | Planned |
| 14 | Extra 2: The politics of carbon taxation | Planned |

## Quickstart

Needs [Julia](https://julialang.org/downloads/) 1.10+ and
[Quarto](https://quarto.org/docs/get-started/) 1.5+. On Windows both are one winget command
each — see [Setup](https://nehalahmedshaikh.github.io/doing-economics/setup.html) for
the full walkthrough, including macOS and Linux.

```bash
git clone https://github.com/nehalahmedshaikh/doing-economics
cd doing-economics

julia --project=. -e 'using Pkg; Pkg.instantiate()'   # exact versions from Manifest.toml
quarto render projects/01-measuring-climate-change/index.qmd          # data is included
```

## Layout

```
├── projects/            one directory per empirical project
│   ├── 01-measuring-climate-change/index.qmd
│   ├── 02-data-from-experiments/index.qmd
│   ├── 03-sugar-tax/index.qmd
│   ├── 04-measuring-wellbeing/index.qmd
│   ├── 05-measuring-inequality/index.qmd
│   ├── 06-management-practices/index.qmd
│   └── 07-supply-and-demand/index.qmd
├── src/DoingEconomics.jl   shared helpers: paths, chart theme, gini/lorenz,
│                           frequency tables, index numbers, verified downloads
├── data/
│   ├── MANIFEST.toml    every dataset: url, checksum, licence, vintage
│   └── raw/             the datasets themselves, committed (7.9 MB)
├── scripts/
│   ├── fetch_data.jl    re-download to refresh the series that change
│   └── verify_data.jl   check the working copy against the manifest
├── reference/           R → Julia translation table, statistical definitions
└── test/runtests.jl     tests for the statistical helpers
```

## The stack

| Purpose | Packages |
|---|---|
| Data | [DataFrames.jl](https://dataframes.juliadata.org), [CSV.jl](https://csv.juliadata.org), [XLSX.jl](https://felipenoris.github.io/XLSX.jl), [ReadStatTables.jl](https://junyuan-chen.github.io/ReadStatTables.jl) |
| Statistics | [StatsBase.jl](https://juliastats.org/StatsBase.jl), [HypothesisTests.jl](https://juliastats.org/HypothesisTests.jl) |
| Charts | [AlgebraOfGraphics.jl](https://aog.makie.org) on [CairoMakie](https://docs.makie.org) |
| Pages | [Quarto](https://quarto.org) with its native Julia engine |

Packages are added per project, so the environment carries only what the completed work uses —
regression packages arrive with the projects that need them. `Manifest.toml` is committed for
exact reproducibility.

## Data

The datasets are committed, under `data/raw/` — 7.9 MB, which makes the repository work
offline and stops it decaying as sources move. That is not hypothetical: Project 5's
upstream, the Global Consumption and Income Project site, has been taken over by an
unrelated operation, and the copy here came from a pre-takeover Internet Archive capture.

`data/MANIFEST.toml` is the provenance record — publisher, licence, SHA-256 and vintage for
every file. Licensing was checked per file: most are public domain (NASA, NOAA) or CC BY
(UNDP, World Bank, Our World in Data) or free-with-attribution (UN Statistics Division).

Files are kept in the format they arrived in. Reading an xlsx, a Stata `.dta` and a zipped
CSV are each part of what the book teaches, so they are not normalised.

`scripts/verify_data.jl` checks the working copy against the manifest.
`scripts/fetch_data.jl` re-downloads, which is what you run to refresh the series that
change — NASA GISS is reissued monthly, the World Bank revises continuously.

## Licence

Julia code and prose: [MIT](LICENSE).

The projects, questions, and published solutions are the work of
[CORE Econ](https://www.core-econ.org) and remain their copyright. This repository restates the
tasks in its own words and links to the source pages. Datasets belong to their publishers and
are downloaded from source, not redistributed.
