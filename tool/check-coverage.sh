#!/usr/bin/env bash
set -euo pipefail

# Enforce the line-coverage floor (CLAUDE.md §3) from an lcov report.
#
# Usage: tool/check-coverage.sh [lcov-file] [floor-percent]
#
# lcov `DA:` records are `DA:<line>,<hit-count>[,<checksum>]`. A line counts as
# covered when the hit count is non-zero. The whole computation is ONE awk pass
# — never a pipeline that feeds a count into a filter, which CLAUDE.md names as
# a way a gate silently always-passes.
#
# An lcov file with zero DA: records is an ERROR, not 0% and not a pass: it
# means the run produced no coverage data at all, and a gate that congratulates
# you for measuring nothing is worse than no gate.
#
# THE PERCENTAGE FLOOR IS NOT WHAT PROTECTS A DIFF, and saying so out loud is
# the point of MAX_UNCOVERED below. A tree-wide 50% floor over a 726-line
# codebase tolerates ~726 uncovered lines — an entire second codebase — so
# measured against the real M2 baseline, adding 6 untested lines reported
# `99% (726/732)` and exited 0, and 100 untested lines reported `87%` and exited
# 0. Only 727 of them failed. The reported 100% was a fact about the tree, not
# something this gate enforced.
#
# MAX_UNCOVERED is the ratchet that closes that: an absolute count of uncovered
# lines, committed, which may only ever fall. **The value in force is the third
# argument, passed by `tool/coverage-gate.sh`, not the default below** — read
# that file for the number and for the one time it was not 0. Raising it is a
# deliberate edit to that file, visible in a diff, with a reason in STATE.md —
# not an environment variable, because CLAUDE.md's list of three overrides is
# the complete list and a fourth would be exactly the "undocumented lever that
# quietly lowers a bar" it warns about.
#
# The percentage floor stays, because it is what CLAUDE.md §3 states and because
# the two fail on different things: the ratchet catches an untested function in
# a healthy tree, the floor catches a tree that has stopped being healthy.

LCOV_FILE="${1:-coverage/lcov.info}"
FLOOR="${2:-50}"
TARGET=80
MAX_UNCOVERED="${3:-0}"

if [ ! -f "$LCOV_FILE" ]; then
    echo "ERROR: $LCOV_FILE not found — run 'just coverage' first"
    exit 1
fi

read -r covered total < <(
    awk -F, '
        /^DA:/ { total++; if ($2 + 0 > 0) covered++ }
        END { printf "%d %d\n", covered + 0, total + 0 }
    ' "$LCOV_FILE"
)

if [ "$total" -eq 0 ]; then
    echo "ERROR: no DA: records in $LCOV_FILE — coverage data is missing or empty"
    exit 1
fi

pct=$((covered * 100 / total))
uncovered=$((total - covered))
echo "Coverage: ${pct}% (${covered}/${total} lines), floor ${FLOOR}%, target ${TARGET}%"
echo "Uncovered: ${uncovered} line(s), ratchet ${MAX_UNCOVERED}"

if [ "$pct" -lt "$FLOOR" ]; then
    echo "ERROR: coverage ${pct}% is below the ${FLOOR}% floor"
    exit 1
fi

if [ "$uncovered" -gt "$MAX_UNCOVERED" ]; then
    echo "ERROR: ${uncovered} uncovered line(s), ratchet allows ${MAX_UNCOVERED}."
    echo "       The ${FLOOR}% floor would tolerate about $((total - total * FLOOR / 100))"
    echo "       of them, which is why it is not the thing protecting this diff."
    exit 1
fi

if [ "$uncovered" -lt "$MAX_UNCOVERED" ]; then
    echo "NOTICE: ${uncovered} uncovered line(s) beats the ratchet of ${MAX_UNCOVERED}."
    echo "        Lower MAX_UNCOVERED in tool/coverage-gate.sh to lock it in."
fi

if [ "$pct" -lt "$TARGET" ]; then
    echo "WARN:  coverage ${pct}% is below the ${TARGET}% target"
fi
