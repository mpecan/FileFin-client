#!/usr/bin/env bash
set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$(repo_root)"

# The `just coverage-check` entry point: decides whether coverage is even
# measurable yet, then hands the actual thresholding to check-coverage.sh.
#
# The split is deliberate. check-coverage.sh reads an lcov file and nothing
# else, which is what lets it be proven against hand-made lcov files with known
# ratios. This wrapper owns the single "not yet" case, and that case is gated on
# there being no package at all — the first pubspec.yaml and the real gate runs.

if no_dart_packages; then
    echo "coverage-check: no Dart package in the tree yet — nothing to measure (M0 only)"
    exit 0
fi

# 50 is CLAUDE.md §3's tree-wide floor. The third argument is the one that
# protects a diff: an absolute ratchet on uncovered lines, which may only ever
# fall. See the header of check-coverage.sh for why the percentage alone cannot
# see an untested function.
#
# IT IS 2 AT M4, RAISED FROM 0 FOR THE FIRST TIME, AND HERE IS EXACTLY WHAT THE
# TWO LINES ARE.
#
#   apps/mobile/lib/src/playback/mpv_player.dart, `RealMpvPlayer.buildSurface`:
#     Widget buildSurface() =>
#         Video(controller: _controller ??= VideoController(_player));
#
# `VideoController(player)` **hangs** under `flutter test`. It awaits a platform
# channel `flutter_tester` does not host: a probe that constructed one and
# pumped a `Video` never returned and was killed at five minutes (M4.0). Not
# slow — non-terminating, so this cannot be bought with a longer timeout.
#
# Everything around it IS covered, and that is the measurement that kept this
# number at 2 instead of at a whole file. `media_kit`'s core is pure Dart over
# `dart:ffi`, so a real `Player` constructs headlessly against a host libmpv
# (M4.0/E2): `test/playback/real_mpv_player_test.dart` drives every other
# delegation in that file against a real mpv context, and
# `media_kit_playback_host_test.dart` covers every translation decision against
# a fake. `buildSurface` is on `MpvPlayer` rather than in the translation layer
# precisely so the uncoverable expression is one line in the thinnest file
# rather than a hole in the middle of the logic.
#
# `docs/verification-backlog.md` row 15 is the device experiment that checks
# what these two lines actually do. Lower this the day it is retired with a
# mechanism that can run headlessly; never raise it to make a diff pass.
exec bash tool/check-coverage.sh coverage/lcov.info 50 2
