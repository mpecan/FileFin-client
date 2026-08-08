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
generated_files=$(
    {
        git ls-files -- '*.g.dart' '*.freezed.dart'
        git ls-files --others --exclude-standard -- '*.g.dart' '*.freezed.dart'
    } | sort -u
)
generated=$(printf '%s\n' "$generated_files" | grep -c . || true)

# A `*.g.dart` name is an ESCAPE HATCH, so the name alone may not be trusted.
#
# `dart_lib_sources` (tool/common.sh) excludes `*.g.dart` and `*.freezed.dart`
# by FILENAME, and every gate in the tree is built on it — the ignore-comment
# guard, the missing-coverage-record check, `analyze`'s source list,
# `constitution`, `dupes`, `mutants`, `file-size`, `comments`. So a file merely
# NAMED `*.g.dart` is invisible to all of them at once. Measured before this
# check existed: `lib/src/fake.g.dart` holding `// coverage:ignore-file` and an
# untested `int neverTested(...)` passed `run-coverage.sh` without being
# mentioned, and passed this gate too — staged, which is what a commit looks
# like. That is the widest hole in the tree, opened by a naming convention.
#
# Two facts are asserted about every file wearing the name, and each is a thing
# a builder does and a hand-written file does not:
#
#   1. the generator's own header line. json_serializable and freezed both open
#      with `// GENERATED CODE - DO NOT MODIFY BY HAND`.
#   2. a non-generated sibling that claims it with `part '<name>';`. Both
#      builders emit part-of files, so every legitimate one is named by a
#      library that IS in `dart_lib_sources` and therefore IS gated. This also
#      catches generated output orphaned by the deletion of its source.
#
# A hand-written file can of course type the header out; it cannot also arrange
# for a gated library to declare it a part and still hide its code, because a
# `part` file's contents belong to that library and `analyze` reads them there.
unverified=()
while IFS= read -r gen; do
    [ -n "$gen" ] || continue
    if ! head -1 "$gen" | grep -qF 'GENERATED CODE - DO NOT MODIFY BY HAND'; then
        unverified+=("$gen — no generator header on line 1")
        continue
    fi
    base="${gen%.g.dart}"
    base="${base%.freezed.dart}"
    owner="$base.dart"
    if [ ! -f "$owner" ]; then
        unverified+=("$gen — no $owner to be a part of")
    elif ! grep -qF "part '$(basename "$gen")';" "$owner"; then
        unverified+=("$gen — $owner does not declare it a part")
    fi
done <<< "$generated_files"

if [ ${#unverified[@]} -gt 0 ]; then
    printf '  %s\n' "${unverified[@]}"
    fail "${#unverified[@]} file(s) are named like generated output but are not
       verifiably generated (§10). Every gate in this repo excludes *.g.dart and
       *.freezed.dart by filename, so the name is an opt-out of all of them at
       once. Rename the file, or generate it."
fi

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
    #
    # `--delete-conflicting-outputs` was dropped in the same edit that added the
    # `rm -rf`, and that went unrecorded until a review noticed. Recorded now,
    # with the reason: the flag lets the builder DELETE a file it did not write
    # in order to make its own build succeed, which is an auto-fix inside a gate
    # whose whole job is to notice a difference. Re-verified after the cache
    # deletion landed — a full rebuild over the committed output writes all 20
    # of them with no conflict, so the flag bought nothing and could only have
    # hidden something. `run-codegen.sh` omits it for the same reason.
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
