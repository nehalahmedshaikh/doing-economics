#!/usr/bin/env julia
#
# Download the datasets described in data/MANIFEST.toml into data/raw/.
#
#     julia --project=. scripts/fetch_data.jl          # every project
#     julia --project=. scripts/fetch_data.jl 1        # just project 1
#     julia --project=. scripts/fetch_data.jl 1 5 12   # a few projects
#
# Files already present with a matching checksum are left alone, so re-running this
# is cheap. Sources that require registration are not downloaded; the script prints
# what to do by hand and carries on.

using TOML
using DoingEconomics: rawpath, reporoot, fetch_verified, sha256_file

const MANIFEST = reporoot("data", "MANIFEST.toml")

function load_entries(wanted::Vector{Int})
    isfile(MANIFEST) || error("manifest not found at $MANIFEST")
    entries = get(TOML.parsefile(MANIFEST), "file", Dict{String,Any}[])
    isempty(entries) && error("manifest lists no files")
    isempty(wanted) && return entries
    kept = filter(e -> e["project"] in wanted, entries)
    if isempty(kept)
        asked = join(wanted, ", ")
        known = join(sort(unique(e["project"] for e in entries)), ", ")
        error("no manifest entries for project(s) $asked. Known projects: $known")
    end
    return kept
end

"""    handle_manual(entry) -> Symbol

Report what a human has to do for a registration-gated source, and whether the file
is already sitting where it should be.
"""
function handle_manual(entry)
    dest = rawpath(entry["dest"])
    if isfile(dest)
        println("  present (placed by hand): $(entry["dest"])")
        return :ok
    end
    println("""
      MANUAL STEP REQUIRED - this source cannot be downloaded unattended.
        save to: $dest
        $(rstrip(get(entry, "instructions", "See `url` in data/MANIFEST.toml.")))
    """)
    return :manual
end

function handle_download(entry)
    dest = rawpath(entry["dest"])
    stable = get(entry, "stable", true)
    recorded = get(entry, "sha256", nothing)

    # A frozen source gets its checksum enforced. A source that is legitimately
    # reissued over time is downloaded unverified, then compared with the recorded
    # vintage so drift is visible rather than silent.
    fetch_verified(entry["url"], dest; sha256 = stable ? recorded : nothing)

    if !stable && recorded !== nothing
        got = sha256_file(dest)
        if got != lowercase(recorded)
            println("""
              NOTE: upstream has been reissued since the recorded vintage \
            ($(get(entry, "vintage", "unknown"))).
                recorded: $(lowercase(recorded))
                current:  $got
              Results may differ slightly from the committed figures. This is expected
              for this source; update the manifest when you intend to move vintage.
            """)
            return :drift
        end
    end
    return :ok
end

function main(args)
    wanted = Int[]
    for a in args
        n = tryparse(Int, a)
        n === nothing && error("expected project numbers, got \"$a\"")
        push!(wanted, n)
    end

    entries = load_entries(wanted)
    results = Dict{Symbol,Int}(:ok => 0, :manual => 0, :drift => 0, :failed => 0)

    for entry in entries
        println("[project $(entry["project"])] $(entry["name"])")
        status = try
            get(entry, "manual", false) ? handle_manual(entry) : handle_download(entry)
        catch err
            println("  FAILED: ", sprint(showerror, err))
            :failed
        end
        results[status] += 1
    end

    println("\n", "-"^60)
    println("$(length(entries)) file(s): $(results[:ok]) ready, " *
            "$(results[:drift]) reissued upstream, " *
            "$(results[:manual]) awaiting a manual download, " *
            "$(results[:failed]) failed")

    results[:failed] > 0 && exit(1)
    return nothing
end

# Block form, not `... == @__FILE__ && main(ARGS)`: the macro would swallow the
# `&& main(ARGS)` as its own arguments.
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
