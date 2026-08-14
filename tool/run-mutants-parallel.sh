#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# `just mutants`, sharded across git worktrees so it finishes in an evening.
#
# **THIS IS NOT THE GATE.** `tool/check-mutants.sh` is, it stays in `just
# check`, and it stays the authority on whether a diff is clean. This script
# exists because that gate is diff-scoped and a redesign-sized diff is 859
# mutants at ~16 s each — about four hours serially, which is long enough that
# people stop running it, and a gate nobody runs is a gate you have already
# lost. It answers the same question faster; it does not answer a smaller one.
#
# WHY WORKTREES RATHER THAN A --jobs FLAG. `mutation_test` has none and cannot:
# it rewrites the source file in place and runs the suite against the tree, so
# two concurrent mutants in one tree would test each other's edits. A worktree
# per shard gives each its own copy of the tree to mutate.
#
# WHY THIS IS SAFER THAN THE SERIAL GATE, not just faster. `check-mutants.sh`
# mutates the REAL working tree, so an interrupted run leaves a mutant in it —
# CLAUDE.md names the hazard and it has now happened three times in this
# project, twice in one evening. Nothing here ever writes to the working tree:
# the shards live in worktrees under a scratch root and are removed on exit, so
# a Ctrl-C costs a re-run and nothing else.
#
# WHY NOT A RAM DISK. Measured, and it is 27% SLOWER — see STATE.md's M8
# section. `cargo-mutants` copies the whole tree per job, which is what a RAM
# disk is for; `mutation_test` mutates one tree in place, so there is no copy
# to relocate and a wired HFS+ volume only takes the working set out of the
# page cache it was already living in.
#
# IT SPANS PACKAGES, and until M8.R it refused to. A SHARD is single-package and
# has to be — `mutation_test` takes paths relative to its working directory and
# runs from the package root, and the test command differs (`flutter test` under
# `apps/`, `dart test` under `packages/`) — but shards from different packages
# are just processes, so they all run at once under one job budget.
#
# The refusal was not academic: the M8.R documentation pass spanned all three
# packages, so the only tool that could take it was the serial gate, at about
# ten hours. Looping the packages here instead would have been simpler and
# wrong in its own way — it leaves most cores idle while `filefin_core`'s
# one-second suite works through its share.
#
# THE PER-MUTANT TIMEOUT IS DERIVED PER PACKAGE, and that is the load-bearing
# part of spanning them. It comes from that package's own clean-suite time, and
# the packages differ by about fifty times: `filefin_core` finishes inside a
# second and lands on the 60s floor, `apps/mobile` measures tens of seconds and
# lands in the hundreds. One shared timeout would be wrong for one of them in
# the dangerous direction — apps/mobile's value applied to `filefin_core` lets a
# hung mutant burn ten minutes before anything notices, which is exactly the
# "survivor or hang?" confusion check-mutants.sh exists to keep separable.
#
#   FILEFIN_MUTANTS_BASE=<sha> bash tool/run-mutants-parallel.sh
#   MUTANTS_JOBS=3 FILEFIN_MUTANTS_BASE=<sha> bash tool/run-mutants-parallel.sh
#
# Environment:
#   FILEFIN_MUTANTS_BASE  the diff base, same meaning as in the gate
#   MUTANTS_JOBS          shard count; default is derived from the core count
#   MUTANTS_KEEP=1        leave the worktrees and reports for inspection

BASE="${FILEFIN_MUTANTS_BASE:-HEAD}"
RULES="$(pwd)/mutation_rules.xml"
SCRATCH="${TMPDIR:-/tmp}/filefin-mutants-parallel.$$"
KEEP="${MUTANTS_KEEP:-0}"

fail() { printf '\033[31mmutants-parallel: %s\033[0m\n' "$*" >&2; exit 1; }
say()  { printf '\033[36mmutants-parallel:\033[0m %s\n' "$*" >&2; }

cleanup() {
    local status=$?
    if [ "$KEEP" = "1" ]; then
        say "leaving $SCRATCH in place (MUTANTS_KEEP=1)"
        exit "$status"
    fi
    # `git worktree remove` rather than `rm -rf`: it also drops the
    # administrative entry, and a stale entry makes the NEXT run's `worktree
    # add` fail on a path that no longer exists.
    if [ -d "$SCRATCH" ]; then
        for wt in "$SCRATCH"/wt-*; do
            [ -d "$wt" ] || continue
            git worktree remove --force "$wt" >/dev/null 2>&1 || true
        done
        rm -rf "$SCRATCH"
    fi
    exit "$status"
}
trap cleanup EXIT INT TERM

command -v dart >/dev/null 2>&1 || fail "dart not on PATH"
[ -f "$RULES" ] || fail "mutation_rules.xml not found at $RULES"

# A DIRTY TREE IS REFUSED, and that is not fussiness. A worktree is created
# from a COMMIT, so uncommitted work would silently not be under test — the
# script would report a clean sweep over code the author has not written yet.
# It is also the one condition under which a mutant left by an earlier
# interrupted serial run would be invisible here.
[ -z "$(git status --porcelain)" ] || fail "the working tree is dirty.
       A worktree is made from a commit, so uncommitted changes would not be
       under test and this run would report on code that is not the code.
       Commit or stash first."

# The gate's own comment stripper, copied verbatim rather than approximated.
# A single-line `sed 's|<!--.*-->||'` looked equivalent and was not:
# mutation_rules.xml discusses `<commands>` inside a MULTI-LINE comment, so the
# guard below fired on every run and the driver refused to start. Kept
# character-for-character with check-mutants.sh so the two cannot disagree
# about what a rules document declares.
strip_xml_comments() {
    awk '
        {
            res = ""; line = $0
            while (line != "") {
                if (incomment) {
                    i = index(line, "-->")
                    if (i == 0) { line = "" } else { line = substr(line, i + 3); incomment = 0 }
                } else {
                    i = index(line, "<!--")
                    if (i == 0) { res = res line; line = "" }
                    else { res = res substr(line, 1, i - 1); line = substr(line, i + 4); incomment = 1 }
                }
            }
            print res
        }
    ' "$1"
}

# Same guard the gate applies to its own rules document: a <commands> block
# there runs IN ADDITION to the per-shard command written below, so `dart test`
# would be executed from the repo root where it means nothing.
if strip_xml_comments "$RULES" | grep -qE '<commands[[:space:]]*>'; then
    fail "$RULES declares a <commands> block, which would run in addition to
       the per-shard command this script writes."
fi

# --- what to mutate -----------------------------------------------------------
#
# Computed exactly as tool/check-mutants.sh computes it, and it has to stay that
# way: a file this script drops is a file reported clean without being tested.
# The union assertion further down is what turns a drift here into a failure
# rather than a false pass.
changed=$(
    {
        git diff --name-only "$BASE" -- '*.dart'
        git ls-files --others --exclude-standard -- '*.dart'
    } | sort -u | while IFS= read -r f; do
        case "$f" in */lib/*.dart) ;; *) continue ;; esac
        case "$f" in *.g.dart|*.freezed.dart) continue ;; esac
        [ -f "$f" ] || continue
        echo "$f"
    done
)
[ -n "$changed" ] || { say "no changed Dart lib sources vs $BASE"; exit 0; }

# The same comment-only filter the gate applies, and it has to be the same one
# for the reason the union assertion exists: two drivers that disagree about
# WHICH files to mutate answer different questions while claiming to answer one.
# `mutation_test` never touches a comment, so a file whose code is byte-identical
# to the base would only regenerate the base's own mutants.
before=$(printf '%s\n' "$changed" | wc -l | tr -d ' ')
changed=$(
    printf '%s\n' "$changed" | while IFS= read -r f; do
        [ -n "$f" ] || continue
        file_is_comment_only "$BASE" "$f" || echo "$f"
    done
)
dropped=$(( before - $(printf '%s\n' "$changed" | grep -c . || true) ))
[ "$dropped" -gt 0 ] && say "$dropped file(s) differ only in comments — dropped"
[ -n "$changed" ] || { say "every changed lib source was comments; nothing to mutate"; exit 0; }

# EVERY package in the diff, sharded together rather than one at a time.
#
# A SHARD is single-package and has to be: `mutation_test` takes file paths
# relative to its working directory and is run from the package root, and the
# test command differs (`flutter test` under apps/, `dart test` under
# packages/). But shards from DIFFERENT packages are just processes, so they
# all run at once under one job budget. Looping the packages instead would
# leave most cores idle while `filefin_core`'s one-second suite works through
# its share.
packages=$(printf '%s\n' "$changed" | sed 's|/lib/.*||' | sort -u)
mkdir -p "$SCRATCH"

slug_of() { printf '%s' "$1" | tr '/' '_'; }

# --- per package: the runner, the mutant counts, the baseline, the timeout ----
#
# THE TIMEOUT IS PER PACKAGE AND THAT IS THE LOAD-BEARING PART. It is derived
# from that package's own clean-suite time, and the packages differ by about
# fifty times — `filefin_core` finishes inside a second and lands on the 60s
# floor, `apps/mobile` measures tens of seconds and lands in the hundreds. One
# shared timeout would be wrong for one of them in the dangerous direction:
# apps/mobile's value applied to `filefin_core` would let a hung mutant burn ten
# minutes before being noticed, which is the "reported as a hang" confusion
# check-mutants.sh exists to keep distinguishable.
total=0
for pkg in $packages; do
    slug="$(slug_of "$pkg")"
    [ -f "$pkg/pubspec.yaml" ] || fail "$pkg has changed lib sources but no pubspec.yaml"
    [ -d "$pkg/test" ] || fail "$pkg has changed lib sources but no test/ directory"

    case "$pkg" in
        apps/*)     printf '%s' 'flutter test --no-pub' > "$SCRATCH/cmd-$slug" ;;
        packages/*) printf '%s' 'dart test'             > "$SCRATCH/cmd-$slug" ;;
        *) fail "$pkg is neither under packages/ nor apps/" ;;
    esac
    test_cmd="$(cat "$SCRATCH/cmd-$slug")"

    printf '%s\n' "$changed" | grep "^$pkg/" | sed "s|^$pkg/||" > "$SCRATCH/files-$slug"

    dry="$SCRATCH/dry-$slug.xml"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<mutations version="1.0">'
        echo '  <files>'
        while IFS= read -r f; do printf '    <file>%s</file>\n' "$f"; done < "$SCRATCH/files-$slug"
        echo '  </files>'
        echo '</mutations>'
    } > "$dry"

    say "counting mutants in $pkg ($(wc -l < "$SCRATCH/files-$slug" | tr -d ' ') file(s))…"
    # The dry run EXITS NON-ZERO and that is not a failure: it runs no tests, so
    # every mutation it counts is "undetected" and its own quality gate is F.
    # Under `set -e` that killed the script with "counting" as the last thing on
    # screen, which reads exactly like a hang. The status is discarded; the
    # OUTPUT is what is checked.
    set +e
    (cd "$pkg" && dart run mutation_test --rules "$RULES" -d -o "$SCRATCH/dry-$slug" "$dry") \
        > "$SCRATCH/dry-$slug.out" 2>/dev/null
    set -e
    sed -nE 's|^(.*\.dart) : ([0-9]+) mutations$|\2 \1|p' "$SCRATCH/dry-$slug.out" \
        | sort -rn > "$SCRATCH/counts-$slug"
    [ -s "$SCRATCH/counts-$slug" ] || fail "the dry run produced no per-file counts for
       $pkg — mutation_test's output format may have changed. Run the serial gate."

    pkg_total=$(awk '{s+=$1} END {print s+0}' "$SCRATCH/counts-$slug")
    echo "$pkg_total" > "$SCRATCH/total-$slug"
    total=$(( total + pkg_total ))

    say "measuring $pkg's clean-tree suite baseline…"
    baseline_start=$(date +%s)
    set +e
    (cd "$pkg" && eval "$test_cmd") >/dev/null 2>&1
    baseline_rc=$?
    set -e
    baseline_secs=$(( $(date +%s) - baseline_start ))
    [ "$baseline_rc" -eq 0 ] || fail "$pkg — the suite fails on the UNMUTATED tree."
    [ "$baseline_secs" -lt 5 ] && baseline_secs=5
    [ "$baseline_secs" -gt 120 ] && baseline_secs=120
    pkg_timeout=$(( baseline_secs * 12 ))
    [ "$pkg_timeout" -lt 60 ] && pkg_timeout=60
    echo "$pkg_timeout" > "$SCRATCH/timeout-$slug"
    say "$pkg: $pkg_total mutants, baseline ${baseline_secs}s, per-mutant timeout ${pkg_timeout}s"
done

[ "$total" -gt 0 ] || fail "the dry run counted 0 mutants across the whole diff.
       The serial gate treats that as a condition needing FILEFIN_MUTANTS_ALLOW_ZERO
       and a written reason; it is not something this driver may decide."

# --- split the job budget across packages, by mutant share --------------------
cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc)
# One suite run already saturates about six cores (measured: 634% CPU on an
# M4 Max), so the useful shard count is the core count over that, not the core
# count. Oversubscribing turns a fast sweep into a slow one.
JOBS="${MUTANTS_JOBS:-$(( cores / 6 ))}"
[ "$JOBS" -lt 1 ] && JOBS=1

# Every package with mutants gets at least one shard, so a small package is
# never starved into running after everything else; the rest of the budget goes
# by mutant share. The total may exceed JOBS by at most one shard per package,
# which is the price of not serialising the small ones.
for pkg in $packages; do
    slug="$(slug_of "$pkg")"
    pkg_total=$(cat "$SCRATCH/total-$slug")
    files_n=$(wc -l < "$SCRATCH/files-$slug" | tr -d ' ')
    n=$(( JOBS * pkg_total / total ))
    [ "$n" -lt 1 ] && n=1
    [ "$n" -gt "$files_n" ] && n="$files_n"
    echo "$n" > "$SCRATCH/jobs-$slug"

    # Greedy longest-processing-time first: heaviest file to the lightest shard.
    # LPT is within 4/3 of optimal, and the difference between that and perfect
    # is noise against a sixteen-second mutant.
    awk -v jobs="$n" -v out="$SCRATCH" -v slug="$slug" '
        BEGIN { for (j = 0; j < jobs; j++) load[j] = 0 }
        {
            best = 0
            for (j = 1; j < jobs; j++) if (load[j] < load[best]) best = j
            load[best] += $1
            sub(/^[0-9]+ /, "")
            print $0 >> (out "/shard-" slug "-" best ".txt")
        }
    ' "$SCRATCH/counts-$slug"
done

# THE UNION ASSERTION. Everything above is arithmetic on filenames, and an
# arithmetic slip loses a file silently — the one failure mode a sharded gate
# has that a serial one does not. Reassembled across ALL packages, as full
# paths, and compared against the list the serial gate itself would have used.
sharded="$SCRATCH/sharded.txt"
: > "$sharded"
for pkg in $packages; do
    slug="$(slug_of "$pkg")"
    cat "$SCRATCH"/shard-"$slug"-*.txt 2>/dev/null | sed "s|^|$pkg/|" >> "$sharded"
done
sort -u -o "$sharded" "$sharded"
expected="$SCRATCH/expected.txt"
printf '%s\n' "$changed" | sort -u > "$expected"
if ! diff -q "$expected" "$sharded" >/dev/null; then
    fail "the shards do not reassemble into the changed file list:
$(diff "$expected" "$sharded" || true)"
fi

say "$total mutants across $(printf '%s\n' "$packages" | wc -l | tr -d ' ') package(s), $JOBS-way budget"

# --- run every shard of every package, concurrently ---------------------------
pids=""
for pkg in $packages; do
    slug="$(slug_of "$pkg")"
    test_cmd="$(cat "$SCRATCH/cmd-$slug")"
    cmd_timeout="$(cat "$SCRATCH/timeout-$slug")"
    n=$(cat "$SCRATCH/jobs-$slug")
    for j in $(seq 0 $(( n - 1 ))); do
        list="$SCRATCH/shard-$slug-$j.txt"
        [ -s "$list" ] || continue
        wt="$SCRATCH/wt-$slug-$j"
        git worktree add --detach "$wt" HEAD >/dev/null 2>&1 \
            || fail "could not create a worktree at $wt"
        {
            echo '<?xml version="1.0" encoding="UTF-8"?>'
            echo '<mutations version="1.1">'
            echo '  <commands>'
            printf '    <command group="test" expected-return="0" working-directory="." timeout="%s">%s</command>\n' \
                "$cmd_timeout" "$test_cmd"
            echo '  </commands>'
            echo '  <files>'
            while IFS= read -r f; do printf '    <file>%s</file>\n' "$f"; done < "$list"
            echo '  </files>'
            echo '</mutations>'
        } > "$wt/targets-$slug-$j.xml"

        (
            cd "$wt/$pkg" || exit 1
            # `pub get` rather than the workspace's resolved state: a fresh
            # worktree has no .dart_tool, and `--no-pub` in the test command
            # means the run would fail on the first mutant rather than resolve.
            flutter pub get >/dev/null 2>&1 || dart pub get >/dev/null 2>&1
            log="$SCRATCH/out-$slug-$j.txt"
            rc=0
            dart run mutation_test --rules "$RULES" -f md \
                -o "$SCRATCH/report-$slug-$j" "$wt/targets-$slug-$j.xml" \
                > "$log" 2>&1 || rc=$?
            # mutation_test aborts on its own baseline check when the suite
            # fails on unmodified code — correct in general, and wrong for the
            # one file that crashes its own runner about once in twenty runs.
            # The first whole-tree sweep lost a 472-mutant shard to exactly
            # this, forty seconds in. Retried ONCE, and only for that crash.
            if [ "$rc" -ne 0 ] && mutation_aborted_on_known_flake "$(cat "$log")"; then
                echo "NOTICE: shard $slug-$j — $FLAKY_CRASH_FILE crashed its own" >&2
                echo "        shell during mutation_test's baseline check, so no" >&2
                echo "        mutant was measured. RETRYING ONCE, and once only." >&2
                rc=0
                dart run mutation_test --rules "$RULES" -f md \
                    -o "$SCRATCH/report-$slug-$j" "$wt/targets-$slug-$j.xml" \
                    > "$log" 2>&1 || rc=$?
            fi
            exit "$rc"
        ) &
        pids="$pids $!:$slug-$j"
        say "shard $slug-$j started ($(wc -l < "$list" | tr -d ' ') file(s), timeout ${cmd_timeout}s)"
    done
done
status=0
for entry in $pids; do
    pid="${entry%%:*}"; j="${entry##*:}"
    if wait "$pid"; then
        say "shard $j: all mutants killed"
    else
        status=1
        say "shard $j: FAILED — see $SCRATCH/out-$j.txt"
        grep -iE "not detected|Undetected Mutations|Timeouts" "$SCRATCH/out-$j.txt" | tail -3 >&2 || true
    fi
done

if [ "$status" -ne 0 ]; then
    # The reports are what name the surviving mutants, so they outlive the
    # worktrees whatever KEEP says — a failure with nothing to read is a
    # failure nobody can act on.
    keep_dir="$(pwd)/.mutation-survivors"
    rm -rf "$keep_dir"; mkdir -p "$keep_dir"
    cp -R "$SCRATCH"/report-* "$SCRATCH"/out-*.txt "$keep_dir/" 2>/dev/null || true
    fail "undetected mutants. Reports copied to $keep_dir"
fi

say "all $total mutants in the diff vs $BASE were killed"
