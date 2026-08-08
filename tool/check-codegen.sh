#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Generated code is committed and verified fresh (CLAUDE.md §10).
#
# Regenerate, then fail on any diff. A diff means someone hand-edited generated
# output or changed a model without rerunning the builder — either way a clean
# checkout would not build the same thing this one does.
#
# The second check below is the one that stops this gate going vacuous: if
# *.g.dart / *.freezed.dart files exist but no package declares build_runner,
# then nothing regenerates them, `git diff` is trivially empty, and the gate
# would pass while guarding nothing.

# Tracked AND untracked. `git ls-files` alone missed generated output a builder
# had just produced but nobody had committed, so the anti-vacuity check below
# read "nothing to verify" over exactly the files §10 exists to police.
generated=$(
    {
        git ls-files -- '*.g.dart' '*.freezed.dart'
        git ls-files --others --exclude-standard -- '*.g.dart' '*.freezed.dart'
    } | sort -u | grep -c . || true
)

codegen_pkgs=()
while IFS= read -r pubspec; do
    grep -qE '^[[:space:]]+build_runner:' "$pubspec" || continue
    codegen_pkgs+=("$(dirname "$pubspec")")
done < <(find packages apps -mindepth 2 -maxdepth 2 -name pubspec.yaml 2>/dev/null | sort)

if [ ${#codegen_pkgs[@]} -eq 0 ]; then
    if [ "$generated" -gt 0 ]; then
        fail "$generated generated file(s) are committed but no package declares build_runner —
       nothing can regenerate them, so this gate would verify nothing (§10)"
    fi
    echo "codegen: no package uses build_runner and no generated files are committed — nothing to verify"
    exit 0
fi

for pkg in "${codegen_pkgs[@]}"; do
    echo "codegen: $pkg"
    # The build cache is deleted first, and that is the whole difference between
    # this gate working and not working. build_runner is incremental: it hashes
    # its own outputs, and on an unchanged input it reports "30 skipped, wrote 0
    # outputs" WITHOUT looking at what is on disk. Measured: hand-edit one key in
    # a committed `*.g.dart`, `git add` it, run this gate — build_runner skipped,
    # `git diff` had nothing to compare against, and the gate reported "generated
    # output is up to date" over output nobody generated. That is §10 failing
    # silently at exactly the moment it exists for.
    #
    # Only the cache is removed, never the generated files: `build_runner clean`
    # deletes them from the worktree, so a build that then fails leaves the tree
    # gutted. Costs ~10s per package for a full rebuild.
    rm -rf "$pkg/.dart_tool/build"
    (cd "$pkg" && dart run build_runner build)
done

if ! git diff --exit-code -- '*.g.dart' '*.freezed.dart'; then
    fail "regenerating changed committed output (§10).
       Either generated code was hand-edited, or a model changed without
       rerunning the builder (M1.4's `just codegen`). Commit the regenerated files."
fi

# Untracked generated output means a new builder produced a file nobody
# committed; §10 requires a clean checkout to build without running codegen.
untracked=$(git ls-files --others --exclude-standard -- '*.g.dart' '*.freezed.dart')
if [ -n "$untracked" ]; then
    echo "$untracked" | sed 's/^/  /'
    fail "generated files exist but are not committed (§10)"
fi

echo "codegen: generated output is up to date"
