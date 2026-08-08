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

# Every non-generated Dart source we own, one per line.
#
# NEWLINE-separated, so a path containing a newline would corrupt the list — but
# a path containing a SPACE is fine and must stay fine. Callers read this with
# `while IFS= read -r f` into an array and expand it as "${arr[@]}". An
# unquoted `$(dart_sources)` word-splits on IFS, which includes the space, and
# that silently disabled all six checks in check-constitution.sh. This comment
# previously claimed the constraint was "NUL-free paths", which misstates it:
# the split is on whitespace, not NUL, and the difference is the whole bug.
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

# True while no Dart package exists yet — the ONLY condition under which a gate
# may exit 0 without measuring anything (M0).
#
# The guard keys on `pubspec.yaml`, not on `dart_sources` being empty, and that
# distinction is load-bearing: `dart_sources` excludes `*.g.dart` and
# `*.freezed.dart`, so a tree whose only Dart is generated made every M0-only
# branch go green again — long after M0, and precisely over code nobody wrote a
# test for. A pubspec.yaml cannot be excluded away; it is what makes a directory
# a package, and the first one that lands makes all of these branches
# unreachable for good.
no_dart_packages() {
    [ -z "$(find packages apps -mindepth 2 -maxdepth 2 -name pubspec.yaml 2>/dev/null)" ]
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
