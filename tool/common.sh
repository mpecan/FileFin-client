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

# --- the flake tax (CLAUDE.md, M7.7) ----------------------------------------
#
# THE ONE TEST FILE THAT KILLS ITS OWN RUNNER, and the only retry in this repo.
#
# `apps/mobile/test/playback/real_mpv_player_test.dart` loads a real libmpv over
# dart:ffi. Roughly one app-suite run in twenty, the `flutter_tester` shell
# hosting that file dies of a memory fault instead of reporting a result:
# `TestDeviceException(Shell subprocess crashed with unexpected exit code -10.)`
# — SIGBUS — or, less often, an outright segmentation fault. The whole file goes
# with it and every test in it reports "did not complete", including ones that
# had not started.
#
# MEASURED, not inferred (M7.0/E-8, this machine, mpv 0.41.0, Flutter 3.44.9):
#
#   * 2 crashes in 42 plain `flutter test` runs of `apps/mobile` — 4.8%;
#   * 0 crashes in 12 `flutter test --coverage` runs of the same suite;
#   * `ps -eo pid,etime,command | grep flutter_tester` showed ZERO processes
#     before every single iteration, so the orphaned-tester hypothesis
#     CLAUDE.md raises is not what this is;
#   * M6.0/E-9 measured 0 in 24 standalone runs at both concurrencies, which is
#     entirely consistent with 4.8% (P(0 of 24) = 0.31) — the "standalone runs
#     never crash" reading of that result was underpowered, not wrong.
#
# The rate explains the observed "one gate run in four": `just check` runs this
# suite for `test`, again for `coverage`, and once per mutant for `mutants`.
#
# WHY A RETRY, AND WHY NOT THE OTHER TWO OPTIONS the M7 plan offered.
# Giving the file its own `flutter test` invocation makes a human re-run cheap;
# it does not stop the gate going red, and "re-run on red" is the habit that
# hides a real failure — the thing this exists to remove. Fixing the cause means
# fixing a crash inside libmpv's teardown or media_kit's FFI finalizers, neither
# of which is ours and neither of which we can reproduce on demand. So: retry,
# **bounded at one**, **loud**, and **narrow**.
#
# WHAT IT WILL NOT DO, which is the load-bearing half:
#
#   * it does not retry a FAILED ASSERTION. The runner exiting non-zero with
#     test results is a red gate, full stop; only a crashed shell qualifies;
#   * it does not retry a crash in ANY OTHER FILE. A new file killing its
#     runner is new information and must be seen. The predicate reads the
#     `[E]` lines — which the expanded reporter always emits in full, unlike
#     the "Failing tests:" summary, which truncates with "... and N more" — and
#     refuses unless the only file named is the known one;
#   * it does not retry twice. A second crash is reported as the failure it is.
#
# Every retry prints a NOTICE naming the file and the crash, so the rate stays
# measurable instead of becoming folklore. `docs/verification-backlog.md` row H
# carries the retirement condition.
FLAKY_CRASH_FILE='real_mpv_player_test.dart'

# True when $1 (a captured run's output) is a crash of ONLY the known file.
crash_is_known_flake() {
    local out="$1" files
    grep -qF 'Shell subprocess crashed' <<< "$out" || return 1
    files=$(grep -F '[E]' <<< "$out" | grep -oE '[^ /]*_test\.dart' | sort -u)
    [ "$files" = "$FLAKY_CRASH_FILE" ]
}

# True when a `mutation_test` run aborted on ITS OWN baseline check because the
# known libmpv flake crashed the suite, rather than because the suite is red.
#
# mutation_test runs the test command against unmodified code before it mutates
# anything and aborts if that fails — correctly, since every mutant would
# otherwise read as undetected. But it has no notion of a flaky suite, and it
# gives the two cases one message. At the measured ~4.8% per run this aborts a
# whole shard roughly one time in twenty, and the first whole-tree sweep lost
# 472 mutants to exactly that.
#
# It is deliberately NARROW, and inherits every guarantee `crash_is_known_flake`
# already states: only a crashed shell qualifies, only in the one known file,
# and a genuinely red suite is still a red gate. It only adds the requirement
# that the abort came from the baseline check rather than from a mutant.
mutation_aborted_on_known_flake() {
    local out="$1"
    grep -qF 'failed with unmodified code' <<< "$out" || return 1
    crash_is_known_flake "$out"
}

# Run a test command, retrying ONCE if and only if the run died of the known
# libmpv crash. Prints the run's output either way; leaves it in $LAST_TEST_OUT
# for a caller that wants to assert on it. Usage:
#   run_tests_retrying_known_crash <dir> <command...>
#
# `cmd || rc=$?` rather than `set +e; cmd; rc=$?; set -e`, and the difference
# was a real defect for one measurement. `set -e` is SHELL-WIDE, not scoped to a
# function, so the inner `set -e` re-armed errexit inside a caller that had
# deliberately disarmed it — and the final `return "$rc"` then killed the script
# on the spot. The gate still exited 1, but `fail`'s message never printed:
# a gate that fails for the right reason and says nothing about it. Caught by
# proving the negative direction, not by reading the code.
run_tests_retrying_known_crash() {
    local dir="$1"; shift
    local rc=0
    LAST_TEST_OUT=$( (cd "$dir" && "$@") 2>&1 ) || rc=$?
    if [ "$rc" -ne 0 ] && crash_is_known_flake "$LAST_TEST_OUT"; then
        printf '%s\n' "$LAST_TEST_OUT"
        echo "NOTICE: $dir — $FLAKY_CRASH_FILE crashed its own test shell."
        echo "        No test in it reported a result, so this is not a red"
        echo "        suite; it is the libmpv teardown flake measured at"
        echo "        M7.0/E-8 (2 in 42 runs). RETRYING ONCE, and once only."
        echo "        If the retry also crashes, the gate fails. If this NOTICE"
        echo "        starts appearing on most runs, the rate has changed and"
        echo "        docs/verification-backlog.md row H is due again."
        rc=0
        LAST_TEST_OUT=$( (cd "$dir" && "$@") 2>&1 ) || rc=$?
    fi
    printf '%s\n' "$LAST_TEST_OUT"
    return "$rc"
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

# --- comment-only diffs (used by check-mutants.sh) ---------------------------
#
# `mutation_test` rewrites operators, literals and conditions and never touches
# a comment, so a file whose CODE is byte-identical to the base generates
# exactly the base's mutants. Running them re-verifies the existing suite
# against existing code and says nothing about the diff.
#
# Lives here rather than inline in the gate so it can be proven on its own,
# WITHOUT starting a mutation run. That is not tidiness: proving it by killing a
# live `mutation_test` is what leaves a mutant on disk, and doing exactly that
# is how this function's first proof attempt corrupted engine.dart
# (`if (!(pointer == null)`) — the hazard CLAUDE.md names, re-created by the
# harness meant to test the fix for it.

# Drop whole-line comments, trailing whitespace and blank lines from stdin.
strip_comment_lines() {
    sed -e 's/[[:space:]]*$//' -e '/^[[:space:]]*\/\//d' -e '/^[[:space:]]*$/d'
}

# True when [file] differs from [base] only in whole-line comments.
#
# PER FILE, and that granularity is the point. The first version answered for a
# whole diff at once, so a single changed line of code anywhere dragged every
# comment-only file in the diff into the mutation run with it: a documentation
# pass that also corrected two user-facing strings put 59 files in front of
# `mutation_test` to learn something about two. The caller filters instead.
# FAILS CLOSED. Anything that is not a whole-line comment — a trailing `// note`
# on a statement, a line that stops being code, a brace that moved — survives
# the strip and is a difference, so the answer is "no" and the caller mutates
# the file. It can only ever fail to skip; it cannot skip a real change.
#
# Two shapes are refused outright rather than analysed: a file that does not
# exist in [base] (new code, nothing to compare), and a file holding a
# multi-line string, whose lines a line-based strip cannot tell from comments.
file_is_comment_only() {
    local base="$1" f="$2"
    git cat-file -e "$base:$f" 2>/dev/null || return 1
    grep -q -e "'''" -e '"""' "$f" && return 1
    diff -q \
        <(git show "$base:$f" | strip_comment_lines) \
        <(strip_comment_lines < "$f") >/dev/null
}

# True when EVERY file on stdin is comment-only. Kept for the proof harness and
# for a caller that wants the all-or-nothing answer.
changes_are_comment_only() {
    local base="$1" f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        file_is_comment_only "$base" "$f" || return 1
    done
    return 0
}
