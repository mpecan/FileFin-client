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
    echo "coverage: $pkg_dir"
    (cd "$pkg_dir" && dart test --coverage="../../$OUT/raw/$(basename "$pkg_dir")")
    dart run coverage:format_coverage \
        --lcov \
        --in="$OUT/raw/$(basename "$pkg_dir")" \
        --out="$OUT/$(basename "$pkg_dir").lcov" \
        --packages="$pkg_dir/.dart_tool/package_config.json" \
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
missing=()
while IFS= read -r src; do
    [ -n "$src" ] || continue
    # SF: paths may be absolute or repo-relative depending on how the package
    # was resolved, so the match is anchored on the repo-relative suffix.
    grep -qE "^SF:(.*/)?${src//./\\.}\$" "$LCOV" || missing+=("$src")
done < <(dart_lib_sources)

if [ ${#missing[@]} -gt 0 ]; then
    printf '  %s\n' "${missing[@]}"
    fail "${#missing[@]} lib source(s) produced no coverage record at all.
       No test imports them, so they are missing from the denominator rather
       than sitting at 0% — the floor cannot see them. Import them from a test,
       or delete them (§1)."
fi

echo "coverage: wrote $LCOV from $measured package(s), covering every lib source"
