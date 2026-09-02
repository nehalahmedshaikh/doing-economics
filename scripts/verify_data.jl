#!/usr/bin/env julia
#
# Check what is in data/raw/ against data/MANIFEST.toml. Downloads nothing.
#
#     julia --project=. scripts/verify_data.jl
#     julia --project=. scripts/verify_data.jl 1
#
# Exit status is 1 if any file is missing or a frozen source fails its checksum.
# A reissued source whose checksum has moved on is reported but does not fail the
# run - that is normal for series like NASA GISS.

using TOML
using DoingEconomics: rawpath, reporoot, sha256_file

const MANIFEST = reporoot("data", "MANIFEST.toml")

function status_of(entry)
    dest = rawpath(entry["dest"])
    isfile(dest) || return (:missing, "not downloaded")

    recorded = get(entry, "sha256", nothing)
    recorded === nothing && return (:ok, "present (no checksum recorded)")

    got = sha256_file(dest)
    got == lowercase(recorded) && return (:ok, "checksum matches")

    return get(entry, "stable", true) ?
        (:mismatch, "checksum MISMATCH against a frozen source") :
        (:drift, "reissued since vintage $(get(entry, "vintage", "unknown"))")
end

function main(args)
    wanted = Int[]
    for a in args
        n = tryparse(Int, a)
        n === nothing && error("expected project numbers, got \"$a\"")
        push!(wanted, n)
    end

    entries = get(TOML.parsefile(MANIFEST), "file", Dict{String,Any}[])
    isempty(wanted) || (entries = filter(e -> e["project"] in wanted, entries))
    isempty(entries) && error("no manifest entries matched")

    label = Dict(:ok => "OK      ", :drift => "REISSUED",
                 :missing => "MISSING ", :mismatch => "MISMATCH")
    bad = 0

    for entry in entries
        state, detail = status_of(entry)
        state in (:missing, :mismatch) && (bad += 1)
        println("$(label[state])  p$(lpad(entry["project"], 2))  " *
                "$(rpad(entry["name"], 26))  $detail")
    end

    println("-"^78)
    if bad == 0
        println("all $(length(entries)) file(s) accounted for")
    else
        println("$bad of $(length(entries)) file(s) need attention - " *
                "run: julia --project=. scripts/fetch_data.jl")
        exit(1)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
