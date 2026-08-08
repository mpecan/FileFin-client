#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# Produce coverage/lcov.info from every pure-Dart package's test suite, for
# tool/check-coverage.sh to read.
#
# The empty-tree branch below is the one place this script can exit 0 without
# measuring anything, and it is gated on `dart_sources` being *completely*
# empty. The moment one Dart file exists, this script must produce real data or
# fail — so the M0 no-op cannot survive into M1 unnoticed. STATE.md records it.

OUT="coverage"
LCOV="$OUT/lcov.info"

if [ -z "$(dart_sources)" ]; then
    echo "coverage: no Dart sources in the tree yet — nothing to measure (M0 only)"
    exit 0
fi

rm -rf "$OUT"
mkdir -p "$OUT"

measured=0
while IFS= read -r pubspec; do
    pkg_dir="$(dirname "$pubspec")"
    [ -d "$pkg_dir/test" ] || continue
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
echo "coverage: wrote $LCOV from $measured package(s)"
