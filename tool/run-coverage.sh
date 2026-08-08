#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Produce coverage/lcov.info from every pure-Dart package's test suite, for
# tool/check-coverage.sh to read.
#
# The empty-tree branch below is the one place this script can exit 0 without
# measuring anything, and it is gated on there being no package at all
# (`no_dart_packages`, tool/common.sh). The first pubspec.yaml makes it
# unreachable for good. STATE.md records it.

OUT="coverage"
LCOV="$OUT/lcov.info"

if no_dart_packages; then
    echo "coverage: no Dart package in the tree yet — nothing to measure (M0 only)"
    exit 0
fi

rm -rf "$OUT"
mkdir -p "$OUT"

measured=0
while IFS= read -r pubspec; do
    pkg_dir="$(dirname "$pubspec")"
    # NOT `continue`. Skipping a package with no test/ dropped it out of the
    # denominator entirely, so `just coverage-check` on a tree where one package
    # was tested and another was not reported a clean 100%. A package with no
    # tests is the thing the floor exists to catch.
    [ -d "$pkg_dir/test" ] || \
        fail "$pkg_dir has no test/ directory. It would be dropped from the coverage
       denominator, which is not 0% — it is invisible. Write a test (§3), or
       delete the package (§1)."
    # In a pub WORKSPACE, `dart pub get` writes ONE package_config.json, at the
    # workspace root — members do not get their own. This line used to name
    # `$pkg_dir/.dart_tool/package_config.json` unconditionally, which was
    # correct for a standalone package and did not exist for the first member
    # that landed: format_coverage printed its usage and the run died on the
    # `cat` below. Prefer the package's own (a non-workspace package, or a
    # future one resolved standalone), fall back to the root's, and fail loudly
    # rather than passing an argument that silently means "no packages".
    pkg_config="$pkg_dir/.dart_tool/package_config.json"
    [ -f "$pkg_config" ] || pkg_config=".dart_tool/package_config.json"
    [ -f "$pkg_config" ] || fail "no package_config.json for $pkg_dir — run 'dart pub get'"
    echo "coverage: $pkg_dir"
    (cd "$pkg_dir" && dart test --coverage="../../$OUT/raw/$(basename "$pkg_dir")")
    dart run coverage:format_coverage \
        --lcov \
        --in="$OUT/raw/$(basename "$pkg_dir")" \
        --out="$OUT/$(basename "$pkg_dir").lcov" \
        --packages="$pkg_config" \
        --report-on="$pkg_dir/lib"
    measured=$((measured + 1))
done < <(find packages apps -mindepth 2 -maxdepth 2 -name pubspec.yaml 2>/dev/null | sort)

if [ "$measured" -eq 0 ]; then
    fail "there are Dart sources but no package has a test/ directory — coverage would be vacuous"
fi

cat "$OUT"/*.lcov > "$LCOV"

# The floor's blind spot, and the reason it could not be breached by adding
# untested code.
#
# `dart test --coverage` collects from the VM service, which reports only the
# libraries the tests actually LOADED. `format_coverage --report-on=lib` filters
# that hitmap; it does not synthesise zero rows for a library nobody imported.
# So a lib/ file no test touches contributes no `DA:` records at all — it is not
# 0%, it is absent from the denominator. Measured: one tested one-line file plus
# an eleven-function file nobody imports reported "100% (1/1 lines)" and passed.
#
# Every non-generated lib source must therefore appear as an `SF:` record. A
# file that does not is not weakly tested, it is untested and unimported —
# unreachable from any test or running path, which §1 forbids and §3 measures.
# Failing here is louder and more honest than inventing a line count for it.
#
# THE ONE EXEMPTION, and it is mechanical rather than a list.
#
# A file with no executable code cannot produce a coverage record however well
# it is exercised: the VM emits a hitmap entry per compiled function, and a
# barrel of `export`s or a set of `extension type` declarations compiles to no
# functions at all. Measured on this tree: `lib/filefin_core.dart` (exports
# only) and `lib/src/ids.dart` (four empty-bodied extension types) are absent
# from the raw `.vm.json` hitmap entirely, even with a test that imports the
# barrel and constructs all four IDs. Requiring a record of them is requiring
# the impossible, and "delete them (§1)" is the wrong answer for a barrel.
#
# So a missing record is excused ONLY when the file is verified, line by line,
# to contain nothing but directives and empty-bodied extension types. There is
# no allowlist and no marker comment: both are things a reviewer can be talked
# past. To be exempt your file must literally have nowhere to put a statement,
# and the exempted files are printed on every run so the set stays visible.
# STATE.md records the decision.
has_no_executable_code() {
    ! sed -E 's|//.*$||' "$1" \
        | grep -vE '^[[:space:]]*$' \
        | grep -qvE '^[[:space:]]*(library[^;]*;|import[[:space:]][^;]*;|export[[:space:]][^;]*;|extension type const [A-Za-z_][A-Za-z0-9_]*\([A-Za-z_][A-Za-z0-9_<>?,[:space:]]*\) implements Object \{\})[[:space:]]*$'
}

missing=()
exempt=()
while IFS= read -r src; do
    [ -n "$src" ] || continue
    # SF: paths may be absolute or repo-relative depending on how the package
    # was resolved, so the match is anchored on the repo-relative suffix.
    if grep -qE "^SF:(.*/)?${src//./\\.}\$" "$LCOV"; then
        continue
    fi
    if has_no_executable_code "$src"; then
        exempt+=("$src")
    else
        missing+=("$src")
    fi
done < <(dart_lib_sources)

if [ ${#missing[@]} -gt 0 ]; then
    printf '  %s\n' "${missing[@]}"
    fail "${#missing[@]} lib source(s) produced no coverage record at all.
       No test imports them, so they are missing from the denominator rather
       than sitting at 0% — the floor cannot see them. Import them from a test,
       or delete them (§1)."
fi

if [ ${#exempt[@]} -gt 0 ]; then
    echo "coverage: ${#exempt[@]} lib source(s) have no executable code and so no record:"
    printf '  %s\n' "${exempt[@]}"
fi

echo "coverage: wrote $LCOV from $measured package(s), covering every lib source"
