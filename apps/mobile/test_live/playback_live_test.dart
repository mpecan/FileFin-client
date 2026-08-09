@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/media_kit_playback_host.dart';
import 'package:filefin_mobile/src/playback/mpv_player.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../test/support/libmpv.dart';
import 'support/live.dart';

/// The milestone's real proof: **libmpv playing the real server's bytes**.
///
/// Everything in the chain is the shipped thing — the `filefin` binary, the
/// seeded H.264 file on disk, the socket, the session cookie minted by
/// `playbackHeaders()`, `MediaKitPlaybackHost`, `RealMpvPlayer`, and mpv's own
/// demuxer and decoder. What is *not* real is the video output:
/// `NativePlayer.test = true` forces `vo=null` and `ao=null`, so nothing
/// rasterises and nothing reaches a speaker. Pixels are
/// `docs/verification-backlog.md` row 16, on a device.
///
/// **The negative control is in its own file**, `playback_no_cookie_test.dart`.
/// `Media`'s constructor reads `httpHeaders ?? cache[uri]?.httpHeaders` from a
/// global static cache keyed by URI — but the null branch is unreachable
/// through this code, because `MediaKitPlaybackHost.open` always passes
/// `request.headers` and `PlaybackRequest.headers` is non-nullable (measured at
/// M4.R/T6). The separate file and the distinguished URI are defence in depth
/// against a future caller that stops passing them, not a live hazard here.
///
/// Every wait is bounded and the failure is a timeout with a name, because the
/// alternative — a bare `await` on a stream that never fires — is a hung gate.
void main() {
  // The engine outlives every test in the file, exactly as it did when the
  // work was in a `setUpAll`: tearing an mpv context down from inside a test
  // body while its streams still have listeners crashes `flutter_tester`
  // outright (SIGBUS, measured at M4.R).
  tearDownAll(() async => _host?.dispose());

  test(
    'the real bytes decode: mpv reports the seeded file is 3 seconds',
    () async {
      // The single assertion that says the cookie worked. Without it the server
      // answers 401, mpv reports a failure on its error stream and no duration
      // ever arrives — which is exactly what the negative-control file asserts.
      final run = await _measured();
      expect(run.duration.inMilliseconds, greaterThan(2500));
      expect(run.duration.inMilliseconds, lessThan(4000));
    },
  );

  test('the engine finds the audio track, with no synthetic entries', () async {
    // F7's audio menu has no other possible source: `fileInfo` carries
    // `subtitles[]` and no audio array at all (SPEC §3.3, C2).
    final run = await _measured();
    expect(run.tracks.audio, isNotEmpty);
    expect(
      run.tracks.audio.map((t) => t.id),
      isNot(contains('auto')),
      reason: "mpv's pseudo-entries are dropped by the adapter",
    );
    expect(run.tracks.audio.map((t) => t.id), isNot(contains('no')));
    expect(run.tracks.audio.single.label, isNotEmpty);
  });

  test('position advances past one second of real playback', () async {
    final run = await _measured();
    expect(run.firstPast1s, greaterThan(const Duration(seconds: 1)));
    expect(run.firstPast1s, lessThanOrEqualTo(run.duration));
  });

  test('a seek lands where it was aimed — BACKWARDS', () async {
    // NF3's functional half. The latency half is on a device, over a LAN
    // (`docs/verification-backlog.md` row 17) — a loopback socket cannot say
    // anything about 500 ms on a phone.
    //
    // **Backwards, and that is the whole test.** The previous version played
    // on and waited for `position >= 1.9 s` after seeking FORWARD to 2 s —
    // which ordinary playback reaches on its own, so a `seek()` replaced by a
    // total no-op left all six tests green and the suite ran 20 s → 3 s
    // (M4.R/T2). It was also a tautology of the `firstWhere` that produced the
    // value. Nothing but a real seek moves position backwards.
    final run = await _measured();
    expect(run.afterBackwardSeek, lessThan(const Duration(seconds: 1)));
    expect(run.beforeBackwardSeek, greaterThan(const Duration(seconds: 2)));
  });

  test('completion arrives at the END of the real file', () async {
    // The trigger for the `ended` report, and the only one that carries
    // `position: duration` so the 0.90 crossing is unambiguous.
    //
    // `expect(completedFired, isTrue)` was all this used to say, and
    // `firstWhere((done) => done)` can only complete with `true` — so
    // `completed` replaced by `Stream.value(true)` left every test green and
    // collapsed the suite 20 s → 1 s, taking the proof that the real bytes
    // played to the end with it (M4.R/T3). The two assertions that cannot be
    // faked are WHERE playback had got to and HOW LONG it took to get there.
    final run = await _measured();
    expect(run.completedFired, isTrue);
    expect(
      run.positionAtCompletion.inMilliseconds,
      closeTo(run.duration.inMilliseconds, 500),
    );
    expect(run.playedFor, greaterThan(const Duration(seconds: 1)));
  });

  test('a sidecar fetched through the API renders as a real cue', () async {
    // E4, end to end: the server's own `text/vtt`, fetched with the cookie
    // through `LibraryApi`, handed to `SubtitleTrack.data`, rendered by mpv.
    // Nothing here went through libmpv's own unauthenticated HTTP, which is
    // why `SubtitleSource` carries text rather than a URL.
    final run = await _measured();
    expect(run.subtitleCue.join(' '), contains('Hello fixture'));
  });
}

/// One real playback session, measured once and awaited by every test above.
///
/// **A memoised future rather than a `setUpAll`, and that is a gate rather
/// than a style.** With the work in `setUpAll` every failure reports as
/// `(setUpAll)` and the whole file collapses to a single result: under one
/// deliberate mutation the run was `+0 -1` — five of the six tests never ran
/// and the count silently dropped from 6 to 1, with `run-integration.sh`'s
/// per-SUITE floor of 15 as the only backstop (M4.R/T4). Awaited from each
/// body, the work still happens exactly once and every test keeps its own
/// name, its own pass and its own failure.
Future<_Run>? _memo;
Future<_Run> _measured() => _memo ??= _measure();

/// The engine the memo built, disposed by `tearDownAll` and nowhere else.
MediaKitPlaybackHost? _host;

/// What one session of real playback produced.
class _Run {
  const _Run({
    required this.duration,
    required this.tracks,
    required this.firstPast1s,
    required this.beforeBackwardSeek,
    required this.afterBackwardSeek,
    required this.completedFired,
    required this.positionAtCompletion,
    required this.playedFor,
    required this.subtitleCue,
  });

  final Duration duration;
  final PlaybackTracks tracks;
  final Duration firstPast1s;
  final Duration beforeBackwardSeek;
  final Duration afterBackwardSeek;
  final bool completedFired;
  final Duration positionAtCompletion;
  final Duration playedFor;
  final List<String> subtitleCue;
}

Future<_Run> _measure() async {
  HttpOverrides.global = null;
  ensureLibmpv();
  useHeadlessPlayer();

  final api = await liveApi();
  final categories = await api.categories();
  final films = categories.firstWhere((c) => c.leaf == 'Films');
  final film = (await api.categoryMedia(films.id)).single;
  final detail = await api.mediaDetail(film.id);
  final sidecar = detail.files.single.subtitles.single;

  // THE COOKIE IS FETCHED THE WAY THE PLAYER FETCHES IT. `playbackHeaders()`
  // makes an authenticated `me()` first, so F3 has renewed before the header
  // is handed to an engine that cannot see a status code.
  final headers = await api.playbackHeaders();
  final vtt = await api.subtitleText(
    film.id,
    const FileIndex(0),
    sidecar.index,
  );

  final raw = Player();
  final host = MediaKitPlaybackHost(RealMpvPlayer.over(raw));
  _host = host;

  // Subscribed BEFORE the open, so nothing that arrives during load is
  // missed — mpv reports duration and tracks as part of loading the file.
  final durationSeen = raw.stream.duration.firstWhere((d) => d > Duration.zero);
  final tracksSeen = host.tracks.firstWhere((t) => t.audio.isNotEmpty);
  final past1s = host.position.firstWhere(
    (p) => p > const Duration(seconds: 1),
  );
  final cueSeen = raw.stream.subtitle.firstWhere(
    (lines) => lines.any((l) => l.contains('Hello fixture')),
  );
  final completed = host.completed.firstWhere((done) => done);

  // The furthest mpv ever said it had got. Zeroed again below, immediately
  // before the wait on `completed`, so the value read afterwards describes
  // THAT stretch of playback and no earlier one.
  var furthest = Duration.zero;
  final watching = host.position.listen((p) {
    if (p > furthest) furthest = p;
  });

  final playing = Stopwatch();
  await host.open(
    PlaybackRequest(
      url: api.fileUrl(film.id, const FileIndex(0)),
      headers: headers.headers,
      startAt: Duration.zero,
      // The seeded server is plain HTTP and has no TLS listener at all
      // (§8 R5), so `tls-verify` has nothing to verify here. D10's two other
      // arms are `docs/risks.md` R6's measurement and backlog row 20.
      verifyTls: false,
    ),
  );
  await host.selectSubtitleTrack(
    SubtitleSource(index: sidecar.index, label: 'English', data: vtt),
  );
  await host.play();

  final duration = await durationSeen.timeout(const Duration(seconds: 20));
  final tracks = await tracksSeen.timeout(const Duration(seconds: 20));
  final subtitleCue = await cueSeen.timeout(const Duration(seconds: 20));
  final firstPast1s = await past1s.timeout(const Duration(seconds: 30));

  // Play on to the far side of the file, PAUSE, then seek back. Paused is
  // deliberate: playback resuming from 0.5 s would race the assertion past one
  // second again and hand back a value ordinary playback could have produced.
  final past2_5s = await host.position
      .firstWhere((p) => p > const Duration(milliseconds: 2500))
      .timeout(const Duration(seconds: 30));
  await host.pause();
  final landedBack = host.position.firstWhere(
    (p) => p < const Duration(seconds: 1),
  );
  await host.seek(const Duration(milliseconds: 500));
  final afterBackwardSeek = await landedBack.timeout(
    const Duration(seconds: 20),
  );

  // **Both counters restart here, and that is what makes the two assertions in
  // 'completion arrives at the END' un-fakeable.** Measured first without it:
  // `completed` replaced by `Stream.value(true)` still passed, because
  // `furthest` and the stopwatch had already been fed by the real playback up
  // to 2.5 s above. Reset, a constant `completed` returns from a position of
  // roughly 0.5 s having taken roughly no time, and both assertions fail.
  furthest = Duration.zero;
  playing
    ..reset()
    ..start();
  await host.play();
  final completedFired = await completed.timeout(const Duration(seconds: 40));
  playing.stop();
  final positionAtCompletion = furthest;

  await watching.cancel();

  return _Run(
    duration: duration,
    tracks: tracks,
    firstPast1s: firstPast1s,
    beforeBackwardSeek: past2_5s,
    afterBackwardSeek: afterBackwardSeek,
    completedFired: completedFired,
    positionAtCompletion: positionAtCompletion,
    playedFor: playing.elapsed,
    subtitleCue: subtitleCue,
  );
}
