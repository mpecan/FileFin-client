#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# An uninstalled hook gates nothing and stays silent about it. `check` fails
# rather than warns here, because "warned once, six milestones ago" is
# indistinguishable from "installed" by the time it matters (CLAUDE.md §12).

missing=()
for hook in pre-commit post-commit; do
    if [ ! -e ".git/hooks/$hook" ]; then
        missing+=("$hook")
    elif [ ! -x ".git/hooks/$hook" ]; then
        missing+=("$hook (present but not executable)")
    fi
done

if [ ${#missing[@]} -gt 0 ]; then
    fail "git hooks not installed: ${missing[*]}
       Run 'just install-hooks'. Until then nothing stops a red commit."
fi

echo "hooks: pre-commit + post-commit installed and executable"
