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
# IT IS 0, AND THE ONE TIME IT WAS NOT IS WORTH KEEPING HERE.
#
# M4 raised it to 2 for `RealMpvPlayer.buildSurface`:
#
#   Widget buildSurface() =>
#       Video(controller: _controller ??= VideoController(_player));
#
# on the stated grounds that "`VideoController(player)` **hangs** under
# `flutter test`". **That was false, and it was the only justification the
# first ratchet raise in this project's history ever had.** M4.0's real
# measurement was that a probe which *pumped* a `Video` never returned;
# this file generalised it from pumping to constructing, and coverage only
# ever needed the latter. `media_kit_video-2.0.1`'s constructor body is a
# fire-and-forget `() async { … }()` whose first statement awaits
# `addPostFrameCallback`, so it returns synchronously (`video_controller.dart:71`).
#
# Re-measured at M4.R, three ways, in a plain `test()` body with a binding up:
#   VideoController(player)         -> returns
#   Video(controller: …)            -> returns
#   player.dispose() afterwards     -> NEVER returns
# The last one is the real hazard and it is not the one that was written down:
# `VideoController` sets `isVideoControllerAttached`, and `dispose` then awaits
# a completer that only completes at the end of the closure still parked on the
# post-frame callback. `real_mpv_player_test.dart` covers both lines by giving
# that one test its own `Player` and never disposing it, and additionally pins
# the `??=` memo, which nothing tested before.
#
# `docs/verification-backlog.md` row 16 is the device experiment for what these
# lines actually DRAW, which is a different claim and still open. Never raise
# this to make a diff pass — and if a raise ever is unavoidable, measure the
# claim in the justification before writing it down.
exec bash tool/check-coverage.sh coverage/lcov.info 50 0
