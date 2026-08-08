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
# Files under MIN_LINES counted lines are skipped: on a 6-line file one comment
# is 17% and the ratio says nothing.

WARN_PCT=15
ERROR_PCT=25
MIN_LINES=40

exit_code=0
warnings=0
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

    [ "$total" -lt "$MIN_LINES" ] && continue

    if [ "$pct" -gt "$ERROR_PCT" ]; then
        echo "ERROR: $file is ${pct}% comments (${comments}/${total}, max ${ERROR_PCT}%)"
        errors=$((errors + 1))
        exit_code=1
    elif [ "$pct" -gt "$WARN_PCT" ]; then
        echo "WARN:  $file is ${pct}% comments (${comments}/${total}, target ${WARN_PCT}%)"
        warnings=$((warnings + 1))
    fi
done < <(dart_lib_sources)

echo "comment budget: $errors error(s), $warnings warning(s)"
exit $exit_code
