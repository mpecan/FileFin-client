import 'dart:io';

import 'package:media_kit/media_kit.dart';

/// Where a host libmpv lives on the two platforms this tree is built on.
///
/// macOS is the awkward one and it is measured rather than assumed: `media_kit`
/// 1.2.6's default-name list for macOS is `['Mpv.framework/Mpv']` and nothing
/// else (`native_library.dart:60`), so a Homebrew install is invisible to it —
/// a probe with no `LIBMPV_LIBRARY_PATH` failed with *"Cannot find
/// Mpv.framework/Mpv"* (M4.0/E2b). Linux needs no help: the list carries
/// `libmpv.so.2`, which is exactly what Ubuntu's `libmpv2` package installs
/// (M4.0/E8, measured in an `ubuntu:24.04` container — `apt-get install -y
/// libmpv2` then `dlopen("libmpv.so.2")` succeeded, while the unversioned
/// `libmpv.so` from `libmpv-dev` was absent and is not needed).
const _macCandidates = [
  '/opt/homebrew/opt/mpv/lib/libmpv.dylib',
  '/usr/local/opt/mpv/lib/libmpv.dylib',
];

/// The path [ensureLibmpv] resolved, or null when the platform defaults did.
///
/// Read by the one test that exercises `RealMpvPlayer`'s own constructor: on
/// macOS it has to be handed the same path this file found, because the
/// platform default list cannot see a Homebrew install.
String? resolvedLibmpv;

/// Puts `media_kit` in its headless mode: `vo=null` **and** `ao=null`.
///
/// A one-line function rather than the assignment at each call site, and the
/// reason is a lint rather than taste: `NativePlayer.test` is
/// `@visibleForTesting`, and `dart analyze --fatal-infos --fatal-warnings`
/// counts only `test/` as a test directory. `apps/mobile/test_live/` is a test
/// directory to `just it` and an ordinary library to the analyzer, so the
/// assignment has to live under `test/` — which is where this file already is.
///
/// Without `ao=null` mpv opens an audio device, on a CI box that has none
/// (`real.dart:2507`).
void useHeadlessPlayer() => NativePlayer.test = true;

/// Loads libmpv, or **fails loudly**.
///
/// It never skips, and that is CLAUDE.md's rule rather than a preference: a
/// suite that excuses itself when the interesting dependency is missing reports
/// success over nothing. `just check` therefore requires libmpv on this machine
/// exactly as it requires Flutter, and `check-toolchain.sh` says so first so
/// the failure names the cause instead of arriving from three lines inside a
/// stream listener.
void ensureLibmpv() {
  try {
    // Honours `LIBMPV_LIBRARY_PATH` and then the platform defaults, which is
    // everything CI needs.
    MediaKit.ensureInitialized();
    return;
  } on Object {
    // Fall through to the Homebrew locations below; the real failure is raised
    // there with an install command attached.
  }
  for (final candidate in _macCandidates) {
    if (File(candidate).existsSync()) {
      MediaKit.ensureInitialized(libmpv: candidate);
      resolvedLibmpv = candidate;
      return;
    }
  }
  throw StateError(
    'libmpv could not be loaded, and this suite fails rather than skipping.\n'
    '  macOS: brew install mpv\n'
    '  Debian/Ubuntu: apt-get install -y libmpv2\n'
    'Or point LIBMPV_LIBRARY_PATH at the shared library directly.',
  );
}
