#!/usr/bin/env bash

# Shared helpers for the quality-gate scripts and git hooks in this repo.
#
# Sourced, never executed. Every gate uses the same source-discovery functions
# so "what the gate measures" has exactly one definition — two gates disagreeing
# about which files count is how half a tree stops being checked.

# Print an error and exit 1; the gate scripts' shared failure path.
fail() {
    echo "ERROR: $1"
    exit 1
}

# The directory holding the justfile. Gates are run from `just` (which already
# cds to the root) and from .git/hooks (which does too), but the scripts are
# also run directly during proof runs, so they resolve it themselves.
repo_root() {
    local dir
    dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    while [ "$dir" != "/" ]; do
        [ -f "$dir/justfile" ] && { echo "$dir"; return 0; }
        dir="$(dirname "$dir")"
    done
    echo "ERROR: no justfile found above ${BASH_SOURCE[0]}" >&2
    return 1
}

# Every non-generated Dart source we own, one per line, NUL-free paths only.
#
# `packages` and `apps` may not exist yet (M0 has neither), so `find` is given
# only the roots that do — otherwise it exits 1 and `set -e` kills the gate on
# an empty tree, which would make "no sources" indistinguishable from "broken".
#
# Extra `find` predicates may be appended by the caller.
dart_sources() {
    local roots=()
    local root
    for root in packages apps; do
        [ -d "$root" ] && roots+=("$root")
    done
    [ ${#roots[@]} -eq 0 ] && return 0
    find "${roots[@]}" -name '*.dart' \
        -not -name '*.g.dart' \
        -not -name '*.freezed.dart' \
        -not -path '*/.dart_tool/*' \
        -not -path '*/build/*' \
        "$@"
}

# The subset of dart_sources under a package's `lib/`. This is the "shipping
# code" scope: the comment budget and the constitution checks use it so test
# narration and test-only helpers are not measured as production code
# (docs/architecture.md records that exclusion).
dart_lib_sources() {
    dart_sources -path '*/lib/*' "$@"
}

# Run one gate under a hook: log to a per-process temp file, print ok/FAILED
# with a `[label]` prefix, and on failure print the last 25 log lines indented
# to align with the gate name. Failed gates are appended to the caller's
# global `failed` array so it can block on them.
# Usage: run <label> <name> <command...>
run() {
    local label="$1"; shift
    local name="$1"; shift
    local pad
    pad=$(printf '%*s' "$(( ${#label} + 3 ))" "")
    printf '[%s] %-16s' "$label" "$name"
    if "$@" > "/tmp/filefin-hook-$$.log" 2>&1; then
        echo "ok"
    else
        echo "FAILED"
        tail -25 "/tmp/filefin-hook-$$.log" | sed "s/^/$pad/"
        failed+=("$name")
    fi
    rm -f "/tmp/filefin-hook-$$.log"
}
