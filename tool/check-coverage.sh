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

LCOV_FILE="${1:-coverage/lcov.info}"
FLOOR="${2:-50}"
TARGET=80

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
echo "Coverage: ${pct}% (${covered}/${total} lines), floor ${FLOOR}%, target ${TARGET}%"

if [ "$pct" -lt "$FLOOR" ]; then
    echo "ERROR: coverage ${pct}% is below the ${FLOOR}% floor"
    exit 1
fi

if [ "$pct" -lt "$TARGET" ]; then
    echo "WARN:  coverage ${pct}% is below the ${TARGET}% target"
fi
