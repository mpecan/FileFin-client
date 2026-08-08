#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# `just test`: `dart test` in every package.
#
# The zero-test guard is the point of this script existing rather than the
# recipe calling `dart test` directly. `flutter test` on a package with no test
# files exits 0 — CLAUDE.md names it — and Flutter's runner joins this script at
# M3. Measured on the pinned SDK, `dart test` exits 79 ("No tests were found")
# on an empty test/ and 65 with no test/ at all, so today the guard is
# belt-and-braces; at M3 it is the only thing standing between us and a suite
# that reports success over nothing.
#
# The empty-tree branch is gated on there being no package at all, so it cannot
# survive the arrival of the first one. It used to key on `dart_sources` being
# empty, which excludes generated files — a package whose only Dart was
# `*.g.dart` made this branch reachable again. See `no_dart_packages`.

if no_dart_packages; then
    echo "test: no Dart package in the tree yet — nothing to run (M0 only)"
    exit 0
fi

ran=0
while IFS= read -r pubspec; do
    pkg_dir="$(dirname "$pubspec")"
    count=$(find "$pkg_dir/test" -name '*_test.dart' 2>/dev/null | grep -c . || true)
    if [ "$count" -eq 0 ]; then
        fail "$pkg_dir has no *_test.dart files — a test recipe over zero tests reports success (§3)"
    fi
    echo "test: $pkg_dir ($count test file(s))"
    (cd "$pkg_dir" && dart test)
    ran=$((ran + 1))
done < <(find packages apps -mindepth 2 -maxdepth 2 -name pubspec.yaml 2>/dev/null | sort)

if [ "$ran" -eq 0 ]; then
    fail "a package exists under packages/ or apps/ but nothing was tested"
fi

echo "test: $ran package(s) passed"
