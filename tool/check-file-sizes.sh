#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# File-size gate.
#
# 400 lines is a warning, 600 is an error. Applies to every non-generated Dart
# file under packages/ and apps/, tests included: a 900-line test file is as
# hard to review as a 900-line library (docs/architecture.md records the scope).
#
# `*.g.dart` and `*.freezed.dart` are exempt because nobody reads them and
# nobody can shorten them — the exemption lives in `dart_sources`, so it is the
# same exemption every gate uses.

SOFT_LIMIT=400
HARD_LIMIT=600

exit_code=0
warnings=0
errors=0

# `grep -c ''` counts lines including a final line with no newline, which `wc
# -l` does not.
count_lines() {
    grep -c '' "$1" || true
}

# Process substitution, not a pipe: a `while read` on the right-hand side of a
# pipe runs in a subshell, so `exit_code=1` is discarded and the gate silently
# passes. CLAUDE.md names this failure mode; do not reintroduce it.
while IFS= read -r file; do
    [ -n "$file" ] || continue
    lines=$(count_lines "$file")
    if [ "$lines" -gt "$HARD_LIMIT" ]; then
        echo "ERROR: $file is $lines lines (hard limit: $HARD_LIMIT)"
        errors=$((errors + 1))
        exit_code=1
    elif [ "$lines" -gt "$SOFT_LIMIT" ]; then
        echo "WARN:  $file is $lines lines (soft limit: $SOFT_LIMIT)"
        warnings=$((warnings + 1))
    fi
done < <(dart_sources)

echo "file sizes: $errors error(s), $warnings warning(s)"
exit $exit_code
