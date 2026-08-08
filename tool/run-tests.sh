#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# `just test`: every package's suite, with the right runner.
#
# THE RUNNER IS CHOSEN BY LOCATION, AND CROSS-CHECKED AGAINST THE PUBSPEC.
# `packages/*` is pure Dart and runs `dart test`; `apps/*` is Flutter and runs
# `flutter test` (docs/architecture.md, "Gate scope"). Location is the rule
# because it is the thing a person decides deliberately; the pubspec is the
# thing that drifts. So a disagreement between the two is a hard FAILURE rather
# than the script quietly picking one:
#
#   - `flutter:` sdk-dependency in a `packages/*` pubspec — the purity claim in
#     docs/architecture.md has just been broken, and `dart test` would fail on
#     it later with a message about dart:ui that names nothing;
#   - no `flutter:` in an `apps/*` pubspec — `flutter test` still "works" via
#     the tool's own bundled deps and the package is not what it says it is.
#
# Neither is guessable from the exit code alone, and a runner picked silently
# from the pubspec would EXEMPT a package the moment it changed shape — the
# same defect check_core_purity had at M2 (see tool/check-constitution.sh).
#
# THE ZERO-TEST GUARD is the point of this script existing rather than the
# recipe calling a runner directly. `flutter test` on a package with no test
# files exits 0 — CLAUDE.md names it — and, measured at M3.0 on the pinned
# 3.44.9, so does `flutter test <dir>` when `<dir>` holds no `*_test.dart`: it
# silently runs the package's DEFAULT `test/` directory instead and prints "All
# tests passed!". `dart test` exits 79 on an empty test/ and 65 with none.
#
# THE OUTPUT IS CAPTURED AND ASSERTED ON, for the same two reasons `just it`
# does it (tool/run-integration.sh):
#   ~N  a skipped test still exits 0, under every runner. A grep can only catch
#       the skip syntaxes someone thought of — M2 proved that: `@Skip()`,
#       `solo:` and `markTestSkipped` all evaded one. The runner's own skipped
#       count catches every mechanism, including ones invented later.
#   +N  a suite that ran zero tests while its files still exist. The file count
#       above cannot see that, and `solo:` produces exactly it.
#
# The empty-tree branch is gated on there being no package at all, so it cannot
# survive the arrival of the first one. See `no_dart_packages`.

if no_dart_packages; then
    echo "test: no Dart package in the tree yet — nothing to run (M0 only)"
    exit 0
fi

# True when the pubspec declares the Flutter SDK as a dependency. The shape is
# a two-space-indented `flutter:` key whose child is `sdk: flutter`, which is
# also how `flutter_test` is declared — so the match is on the `sdk: flutter`
# line, which both produce and neither can have without the framework.
declares_flutter() {
    grep -qE '^[[:space:]]+sdk:[[:space:]]*flutter[[:space:]]*$' "$1"
}

ran=0
while IFS= read -r pubspec; do
    pkg_dir="$(dirname "$pubspec")"
    count=$(find "$pkg_dir/test" -name '*_test.dart' 2>/dev/null | grep -c . || true)
    if [ "$count" -eq 0 ]; then
        fail "$pkg_dir has no *_test.dart files — a test recipe over zero tests reports success (§3)"
    fi

    case "$pkg_dir" in
        apps/*)
            runner=(flutter test)
            if ! declares_flutter "$pubspec"; then
                fail "$pkg_dir is under apps/ so it runs 'flutter test', but $pubspec
       declares no 'sdk: flutter' dependency. Either it is not a Flutter app
       and belongs under packages/, or the dependency was deleted. Guessing
       the runner from the pubspec instead would exempt it from this check
       exactly when the pubspec is what changed."
            fi
            ;;
        packages/*)
            runner=(dart test)
            if declares_flutter "$pubspec"; then
                fail "$pkg_dir is under packages/, which docs/architecture.md defines as
       pure Dart, but $pubspec declares an 'sdk: flutter' dependency.
       'dart test' cannot run it and 'just constitution' core_purity says the
       same thing from the other side. Move it to apps/, or drop the
       dependency (§6)."
            fi
            ;;
        *)
            fail "$pkg_dir is neither under packages/ nor apps/, so there is no rule
       for which runner it gets. Add one here before adding the package."
            ;;
    esac

    echo "test: $pkg_dir — ${runner[*]} ($count test file(s))"
    set +e
    out=$( (cd "$pkg_dir" && "${runner[@]}" --reporter expanded) 2>&1 )
    rc=$?
    set -e
    printf '%s\n' "$out"
    [ "$rc" -eq 0 ] || fail "$pkg_dir: ${runner[*]} exited $rc"

    summary=$(printf '%s\n' "$out" | grep -E 'All tests passed!|Some tests failed' | tail -1)
    [ -n "$summary" ] || fail "$pkg_dir: the runner printed no summary line, so it did not run.
       Output above."

    if printf '%s' "$summary" | grep -qE '~[0-9]+'; then
        fail "$pkg_dir reported SKIPPED tests: $summary
       A skipped test reports success while checking nothing. If a case
       cannot run, delete it and say so in STATE.md (§3)."
    fi

    n=$(printf '%s' "$summary" | grep -oE '\+[0-9]+' | tail -1 | tr -d '+')
    [ -n "$n" ] || fail "$pkg_dir: could not read a test count from: $summary"
    if [ "$n" -eq 0 ]; then
        fail "$pkg_dir has $count test file(s) but ran 0 tests. The files exist and
       declare nothing — which the file count above cannot see, and which
       'solo:' produces exactly."
    fi
    echo "test: $pkg_dir — $n test(s)"
    ran=$((ran + 1))
done < <(find packages apps -mindepth 2 -maxdepth 2 -name pubspec.yaml 2>/dev/null | sort)

if [ "$ran" -eq 0 ]; then
    fail "a package exists under packages/ or apps/ but nothing was tested"
fi

echo "test: $ran package(s) passed"
