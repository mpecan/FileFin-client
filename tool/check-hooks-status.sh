#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# An uninstalled hook gates nothing and stays silent about it. `check` fails
# rather than warns here, because "warned once, six milestones ago" is
# indistinguishable from "installed" by the time it matters (CLAUDE.md §12).
#
# "Installed" means the symlink `just install-hooks` writes, resolving to this
# repo's tool/hooks/<name>. Testing only -e/-x accepted ANY executable file,
# so a two-line `exit 0` stub — or a stale copy from before the hook changed —
# passed the gate that exists to prove the gate runs. A copy is rejected too:
# it is a snapshot that silently stops tracking tool/hooks/.

# Absolute, symlink-resolved path of $1. `readlink -f` is GNU-only and
# `realpath` is not on every BSD userland, so this walks the links itself.
resolve() {
    (
        cd "$(dirname "$1")" || return 1
        local p; p="$(basename "$1")"
        while [ -L "$p" ]; do
            local t; t="$(readlink "$p")"
            cd "$(dirname "$t")" || return 1
            p="$(basename "$t")"
        done
        echo "$(pwd -P)/$p"
    )
}

# `git rev-parse`, not a literal `.git/hooks`. In a LINKED WORKTREE `.git` is a
# FILE, so the literal path does not exist and this gate was structurally
# unsatisfiable there — it failed with "not installed" however carefully the
# hooks had been installed. `--git-path hooks` answers with the common hooks
# directory from either kind of checkout, and `--git-common-dir`'s parent is the
# main working tree, which is what the symlink legitimately points into.
hooks_dir="$(git rev-parse --git-path hooks)"
main_tree="$(cd "$(dirname "$(git rev-parse --git-common-dir)")" && pwd -P)"

problems=()
for hook in pre-commit post-commit; do
    installed="$hooks_dir/$hook"
    source_hook="$main_tree/tool/hooks/$hook"
    if [ ! -e "$installed" ]; then
        problems+=("$hook (not installed)")
    elif [ ! -x "$installed" ]; then
        problems+=("$hook (present but not executable)")
    elif [ ! -L "$installed" ]; then
        problems+=("$hook (a plain file, not a symlink to $source_hook)")
    elif [ "$(resolve "$installed")" != "$(resolve "$source_hook")" ]; then
        problems+=("$hook (points at $(resolve "$installed"), not $source_hook)")
    fi
done

if [ ${#problems[@]} -gt 0 ]; then
    fail "git hooks are not the repo's hooks: ${problems[*]}
       Run 'just install-hooks'. Until then nothing stops a red commit."
fi

echo "hooks: pre-commit + post-commit are symlinks to $main_tree/tool/hooks/ and executable"
