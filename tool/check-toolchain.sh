#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# First gate in `just check`. A missing or too-old SDK must fail loudly here,
# because every gate downstream of it would otherwise fail with a confusing
# message about something else — or, worse, "skip" and report success.
#
# 3.8 is the floor, and it is set by the STRICTEST constraint in the tree, not
# by the loosest. Pub workspaces need 3.6, but json_serializable 6.14 refuses to
# generate for a package whose language version is below 3.8 — it warns and
# emits older-shaped output rather than failing, which is the worst of both. The
# floor moves with whatever actually binds; grep the pubspecs for `sdk:` before
# changing it.

MIN_MAJOR=3
MIN_MINOR=8

command -v dart >/dev/null 2>&1 || fail "dart is not on PATH.
       Install the Flutter SDK and add its bin/ to PATH, e.g.
       export PATH=\"\$HOME/development/flutter/bin:\$PATH\""

version="$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
[ -n "$version" ] || fail "could not parse a version out of 'dart --version'"

major="${version%%.*}"
rest="${version#*.}"
minor="${rest%%.*}"

if [ "$major" -lt "$MIN_MAJOR" ] || { [ "$major" -eq "$MIN_MAJOR" ] && [ "$minor" -lt "$MIN_MINOR" ]; }; then
    fail "Dart $version is below the ${MIN_MAJOR}.${MIN_MINOR} floor this workspace needs"
fi

echo "toolchain: dart $version (floor ${MIN_MAJOR}.${MIN_MINOR})"

# Flutter is checked ONLY when a Flutter package exists, and the guard keys on
# an `apps/*/pubspec.yaml` for the same reason `no_dart_packages` keys on one:
# a directory is a package when it has a pubspec, and that cannot be excluded
# away. Before M3 there was no Flutter package and requiring the SDK would have
# been a precondition nothing needed.
#
# From M3 on `just test`, `just coverage` and `just mutants` all invoke
# `flutter test`. Without this the first of them fails with `flutter: command
# not found` from three lines inside a loop, which names the symptom and not
# the cause.
#
# 3.44 is the floor because it is what `apps/mobile` was created against and
# what CI pins (.github/workflows/ci.yml). The interesting number is not the
# framework's but the Dart it bundles: the check above already enforces that,
# and running it first is why a Flutter SDK too old to carry Dart 3.8 fails
# with a message about Dart rather than about Flutter.
FLUTTER_MIN_MAJOR=3
FLUTTER_MIN_MINOR=44

if [ -n "$(find apps -mindepth 2 -maxdepth 2 -name pubspec.yaml 2>/dev/null)" ]; then
    command -v flutter >/dev/null 2>&1 || fail "flutter is not on PATH, and apps/ holds a Flutter package.
       'just test', 'just coverage-check' and 'just mutants' all run
       'flutter test' for it. Add the SDK's bin/ to PATH, e.g.
       export PATH=\"\$HOME/development/flutter/bin:\$PATH\""

    fversion="$(flutter --version 2>&1 | grep -oE 'Flutter [0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    [ -n "$fversion" ] || fail "could not parse a version out of 'flutter --version'"

    fmajor="${fversion%%.*}"
    frest="${fversion#*.}"
    fminor="${frest%%.*}"

    if [ "$fmajor" -lt "$FLUTTER_MIN_MAJOR" ] \
        || { [ "$fmajor" -eq "$FLUTTER_MIN_MAJOR" ] && [ "$fminor" -lt "$FLUTTER_MIN_MINOR" ]; }; then
        fail "Flutter $fversion is below the ${FLUTTER_MIN_MAJOR}.${FLUTTER_MIN_MINOR} floor apps/mobile needs"
    fi

    echo "toolchain: flutter $fversion (floor ${FLUTTER_MIN_MAJOR}.${FLUTTER_MIN_MINOR})"

    # libmpv, from M4.5. `just check` needs it exactly as it needs Flutter, and
    # this is where that stops being a surprise.
    #
    # `apps/mobile/test/playback/real_mpv_player_test.dart` drives a REAL mpv
    # context headlessly — `media_kit`'s core is pure Dart over `dart:ffi` and
    # only `media_kit_video` is a plugin, so a `Player` constructs under
    # `flutter test` (measured, M4.0/E2). That suite FAILS when libmpv is
    # absent rather than skipping, per CLAUDE.md, and without this check the
    # failure arrives from inside a stream listener with no install command
    # attached.
    #
    # The resolution order is `test/support/libmpv.dart`'s, and it is not the
    # obvious one: `media_kit` 1.2.6's macOS default-name list is
    # `['Mpv.framework/Mpv']` and nothing else, so a Homebrew install is
    # invisible to it and the suite passes the path explicitly. Linux needs no
    # help — the list carries `libmpv.so.2`, which is what Ubuntu's `libmpv2`
    # package installs (measured in an ubuntu:24.04 container, M4.0/E8).
    if [ -z "${LIBMPV_LIBRARY_PATH:-}" ]; then
        libmpv_found=""
        for candidate in \
            "$(brew --prefix mpv 2>/dev/null)/lib/libmpv.dylib" \
            /opt/homebrew/opt/mpv/lib/libmpv.dylib \
            /usr/local/opt/mpv/lib/libmpv.dylib; do
            if [ -f "$candidate" ]; then libmpv_found="$candidate"; break; fi
        done
        if [ -z "$libmpv_found" ] && command -v ldconfig >/dev/null 2>&1; then
            if ldconfig -p 2>/dev/null | grep -q 'libmpv\.so\.2'; then
                libmpv_found="$(ldconfig -p | grep -m1 'libmpv\.so\.2')"
            fi
        fi
        [ -n "$libmpv_found" ] || fail "libmpv was not found, and apps/mobile's playback suite needs it.
       'just test' drives a real mpv context headlessly and FAILS rather than
       skipping when it is absent (CLAUDE.md: a suite that can excuse itself
       reports success over nothing). Install it:
         macOS:          brew install mpv
         Debian/Ubuntu:  apt-get install -y libmpv2
       Or export LIBMPV_LIBRARY_PATH pointing at the shared library."
        echo "toolchain: libmpv ${libmpv_found}"
    else
        [ -f "$LIBMPV_LIBRARY_PATH" ] || fail "LIBMPV_LIBRARY_PATH is set to '$LIBMPV_LIBRARY_PATH', which is not a file.
       An environment variable pointing at nothing is worse than an unset one:
       media_kit would fall through to the platform default names and the
       failure would name a framework nobody asked for."
        echo "toolchain: libmpv $LIBMPV_LIBRARY_PATH (from LIBMPV_LIBRARY_PATH)"
    fi
fi
