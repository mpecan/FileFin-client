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

packages=$(printf '%s\n' "$changed" | sed 's|/lib/.*||' | sort -u)
[ "$(printf '%s\n' "$packages" | wc -l)" -eq 1 ] || fail "this driver shards ONE
       package; the diff spans:
$packages
       Run the serial gate, or extend this to loop over packages."
PKG="$packages"
case "$PKG" in
    apps/*)     TEST_CMD='flutter test --no-pub' ;;
    packages/*) TEST_CMD='dart test' ;;
    *) fail "$PKG is neither under packages/ nor apps/" ;;
esac

mkdir -p "$SCRATCH"

# --- balance the shards by MUTANT count, not by file count --------------------
#
# The 38 files of the redesign hold between 1 and 60 mutants each, so an even
# split by filename puts one shard at four times the work of another and the
# run is as slow as that shard. `mutation_test -d` counts without running
# anything, in about two seconds for the whole diff, which is cheap enough to
# do every time rather than guess.
dry="$SCRATCH/dry.xml"
{
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<mutations version="1.0">'
    echo '  <files>'
    printf '%s\n' "$changed" | while IFS= read -r f; do
        printf '    <file>%s</file>\n' "${f#"$PKG"/}"
    done
    echo '  </files>'
    echo '</mutations>'
} > "$dry"

say "counting mutants in $(printf '%s\n' "$changed" | wc -l | tr -d ' ') file(s)…"
counts="$SCRATCH/counts.txt"
# The dry run EXITS NON-ZERO and that is not a failure: it runs no tests, so
# every mutation it counts is "undetected" and the quality gate it applies to
# its own tally is F. Under `set -e` with `pipefail` that killed the script
# three lines into a sweep, with the last thing on screen being the word
# "counting" — which reads exactly like a hang. The status is discarded here
# and the OUTPUT is what gets checked, two lines down.
set +e
(cd "$PKG" && dart run mutation_test --rules "$RULES" -d -o "$SCRATCH/dry" "$dry") \
    > "$SCRATCH/dry.out" 2>/dev/null
set -e
sed -nE 's|^(.*\.dart) : ([0-9]+) mutations$|\2 \1|p' "$SCRATCH/dry.out" \
    | sort -rn > "$counts"
[ -s "$counts" ] || fail "the dry run produced no per-file counts — the output
       format of mutation_test may have changed. Run the serial gate."

total=$(awk '{s+=$1} END {print s+0}' "$counts")
[ "$total" -gt 0 ] || fail "the dry run counted 0 mutants across the whole diff.
       The serial gate treats that as a condition needing FILEFIN_MUTANTS_ALLOW_ZERO
       and a written reason; it is not something this driver may decide."

cores=$(sysctl -n hw.ncpu 2>/dev/null || nproc)
# One suite run already saturates about six cores (measured: 634% CPU on an
# M4 Max), so the useful shard count is the core count over that, not the core
# count. Oversubscribing turns a fast sweep into a slow one.
JOBS="${MUTANTS_JOBS:-$(( cores / 6 ))}"
[ "$JOBS" -lt 1 ] && JOBS=1
files_n=$(printf '%s\n' "$changed" | wc -l | tr -d ' ')
[ "$JOBS" -gt "$files_n" ] && JOBS="$files_n"

# Greedy longest-processing-time first: heaviest file to the lightest shard.
# It is not optimal bin packing and does not need to be — LPT is within 4/3 of
# optimal, and the difference between that and perfect is noise against a
# sixteen-second mutant.
awk -v jobs="$JOBS" -v out="$SCRATCH" -v pkg="$PKG" '
    BEGIN { for (j = 0; j < jobs; j++) load[j] = 0 }
    {
        best = 0
        for (j = 1; j < jobs; j++) if (load[j] < load[best]) best = j
        load[best] += $1
        sub(/^[0-9]+ /, "")
        print $0 >> (out "/shard-" best ".txt")
    }
    END { for (j = 0; j < jobs; j++) printf "shard %d: %d mutants\n", j, load[j] }
' "$counts" >&2

# THE UNION ASSERTION. Everything above is arithmetic on filenames, and an
# arithmetic slip here loses a file silently — which is the one failure mode a
# sharded gate has that a serial one does not. Reassembled and compared against
# the list the gate itself would have used.
sharded="$SCRATCH/sharded.txt"
cat "$SCRATCH"/shard-*.txt 2>/dev/null | sort -u > "$sharded"
expected="$SCRATCH/expected.txt"
printf '%s\n' "$changed" | sed "s|^$PKG/||" | sort -u > "$expected"
if ! diff -q "$expected" "$sharded" >/dev/null; then
    fail "the shards do not reassemble into the changed file list:
$(diff "$expected" "$sharded" || true)"
fi

# --- the suite baseline, and the timeouts derived from it ---------------------
#
# Measured once, in the real tree, exactly as the gate measures it — the same
# clamps and the same 12x multiplier, because a per-mutant timeout is the
# difference between "detected" and "reported as a hang" and the two scripts
# must not disagree about it. See check-mutants.sh for the measurement that
# fixed 12, and for why there is no environment override.
say "measuring the clean-tree suite baseline…"
baseline_start=$(date +%s)
set +e
(cd "$PKG" && eval "$TEST_CMD") >/dev/null 2>&1
baseline_rc=$?
set -e
baseline_secs=$(( $(date +%s) - baseline_start ))
[ "$baseline_rc" -eq 0 ] || fail "$PKG — the suite fails on the UNMUTATED tree."
[ "$baseline_secs" -lt 5 ] && baseline_secs=5
[ "$baseline_secs" -gt 120 ] && baseline_secs=120
cmd_timeout=$(( baseline_secs * 12 ))
[ "$cmd_timeout" -lt 60 ] && cmd_timeout=60

say "$total mutants, $JOBS shard(s), baseline ${baseline_secs}s, per-mutant timeout ${cmd_timeout}s"

# --- run the shards -----------------------------------------------------------
pids=""
for j in $(seq 0 $(( JOBS - 1 ))); do
    list="$SCRATCH/shard-$j.txt"
    [ -s "$list" ] || continue
    wt="$SCRATCH/wt-$j"
    git worktree add --detach "$wt" HEAD >/dev/null 2>&1 \
        || fail "could not create a worktree at $wt"
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<mutations version="1.1">'
        echo '  <commands>'
        printf '    <command group="test" expected-return="0" working-directory="." timeout="%s">%s</command>\n' \
            "$cmd_timeout" "$TEST_CMD"
        echo '  </commands>'
        echo '  <files>'
        while IFS= read -r f; do printf '    <file>%s</file>\n' "$f"; done < "$list"
        echo '  </files>'
        echo '</mutations>'
    } > "$wt/targets.xml"

    (
        cd "$wt/$PKG" || exit 1
        # `flutter pub get` rather than the workspace's resolved state: a fresh
        # worktree has no .dart_tool, and `--no-pub` in the test command means
        # the run would fail on the first mutant rather than resolve for itself.
        flutter pub get >/dev/null 2>&1 || dart pub get >/dev/null 2>&1
        dart run mutation_test --rules "$RULES" -f md -o "$SCRATCH/report-$j" \
            "$wt/targets.xml" > "$SCRATCH/out-$j.txt" 2>&1
    ) &
    pids="$pids $!:$j"
    say "shard $j started ($(wc -l < "$list" | tr -d ' ') file(s))"
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
