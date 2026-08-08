#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Comment budget (CLAUDE.md §2).
#
# Numerator:   explanatory `//` comment lines.
# Denominator: non-blank lines, minus the lines below.
#
# Excluded from BOTH, by design:
#   - `///` doc comments. The budget is about narration, not API documentation;
#     counting them would penalise a declaration-dense wire-model file for
#     documenting its public surface. This exclusion is the single easiest
#     thing to get wrong here, so it has its own proof case in STATE.md.
#   - `// ignore:` and `// ignore_for_file:` — analyzer directives, not prose.
#     They are already justified by the lint they suppress.
#
# Scope is `dart_lib_sources`: test files are excluded because test narration
# is a feature, not debt (docs/architecture.md records this).
#
# Files under MIN_LINES counted lines are skipped, and MIN_LINES IS PART OF THE
# RULE — CLAUDE.md §2 names it, because an undocumented size exemption is a
# blind spot rather than a decision. It was 40 through M3, and at 40 it hid four
# files that were over a line: `filefin_api.dart` at 32%, `filefin_core.dart` at
# 28% and `visible_rows.dart` at 27% were all past the ERROR line while `just
# comments` printed "0 error(s), 0 warning(s)" and STATE.md quoted it. M3.R
# lowered it to 20 and paid all four, by moving the rationale into the `///`
# doc comment of the declaration it is about — which is where it belonged, and
# which §2 excludes from both sides of the ratio.
#
# 20 rather than 0: below twenty counted lines one comment moves the ratio by
# five points or more, so the 15/25 thresholds cannot be stated to the
# precision they are written at. Everything still skipped is listed by the run
# itself (below), so the exemption is visible on every invocation instead of
# being a number in a script nobody opens.

WARN_PCT=15
ERROR_PCT=25
MIN_LINES=20

exit_code=0
warnings=0
skipped=0
errors=0

while IFS= read -r file; do
    [ -n "$file" ] || continue
    read -r pct comments total < <(
        awk '
            {
                if ($0 ~ /^[[:space:]]*$/) next
                if ($0 ~ /^[[:space:]]*\/\/\//) next
                if ($0 ~ /^[[:space:]]*\/\/[[:space:]]*ignore(_for_file)?:/) next
                total++
                if ($0 ~ /^[[:space:]]*\/\//) comments++
            }
            END {
                total = total + 0; comments = comments + 0
                printf "%d %d %d\n", (total > 0 ? (comments * 100) / total : 0), comments, total
            }
        ' "$file"
    )

    # Named, not silently dropped. The old gate skipped in silence, so a file
    # over the ERROR line and a file with nothing to say printed identically —
    # which is how three errors sat behind a summary line reading "0 error(s)".
    if [ "$total" -lt "$MIN_LINES" ]; then
        skipped=$((skipped + 1))
        [ "$pct" -gt "$WARN_PCT" ] &&
            echo "SKIP:  $file is ${pct}% comments (${comments}/${total}, under ${MIN_LINES} counted lines — §2's size exemption)"
        continue
    fi

    if [ "$pct" -gt "$ERROR_PCT" ]; then
        echo "ERROR: $file is ${pct}% comments (${comments}/${total}, max ${ERROR_PCT}%)"
        errors=$((errors + 1))
        exit_code=1
    elif [ "$pct" -gt "$WARN_PCT" ]; then
        echo "WARN:  $file is ${pct}% comments (${comments}/${total}, target ${WARN_PCT}%)"
        warnings=$((warnings + 1))
    fi
done < <(dart_lib_sources)

echo "comment budget: $errors error(s), $warnings warning(s), $skipped file(s) under ${MIN_LINES} counted lines"
exit $exit_code
