@Timeout(Duration(seconds: 180))
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

/// M5's real proof: **libmpv playing the HEVC show through the server's 307.**
///
/// Its own file rather than more cases in `playback_live_test.dart`, and that
/// is a measurement rather than tidiness: tearing down an mpv context whose
/// streams still have listeners crashes `flutter_tester` outright (SIGBUS,
/// M4.R/T4), and `Media`'s `httpHeaders` cache is global and keyed by URI, so
/// two suites sharing a process share more than a process.
///
/// Everything here is the shipped thing — the `filefin` binary, the seeded HEVC
/// file, the socket, the cookie from `playbackHeaders()`, the `307`, the
/// playlist, the segment, `MediaKitPlaybackHost` and `RealMpvPlayer`. What is
/// not real is the video output (`vo=null`); pixels are backlog row 16.
void main() {
  tearDownAll(() async => _host?.dispose());

  test('the HLS stream decodes: mpv reports the playlist duration', () async {
    // **This is the assertion that says the cookie survived onto the
    // segments.** The playlist route and the segment route both sit behind
    // `s.auth` (`server.go:283`), so without the header the server answers 401
    // twice and no duration ever arrives.
    //
    // 3.023 s, not 3.000: mpv takes the duration from `#EXTINF:3.023` in the
    // playlist rather than from the source file (measured, M5.0/E-C), and the
    // 90% crossing is computed against whatever mpv says.
    final run = await _measured();
    expect(run.duration.inMilliseconds, greaterThan(2900));
    expect(run.duration.inMilliseconds, lessThan(3200));
  });

  test('the transcoded stream carries an audio track (F7)', () async {
    final run = await _measured();
    expect(run.tracks.audio, isNotEmpty);
    expect(run.tracks.audio.map((t) => t.id), isNot(contains('auto')));
    expect(run.tracks.audio.map((t) => t.id), isNot(contains('no')));
  });

  test('F8 over HLS: Media(start:) IS honoured on a VOD playlist', () async {
    // **Nothing had ever tested this** and F8 over HLS depends entirely on it
    // (M5.0/E-D). Measured: with `startAt: 1200ms` the position stream reads
    // `[0, 1200, 1289, …]`; with `startAt: 0` it reads `[0, 89, 156, …]`. The
    // control below is what makes the number mean something — 1.2 s is a
    // position ordinary playback reaches on its own within two seconds, so
    // "past 1.2 s" alone would pass against a `start:` mpv ignored.
    final run = await _measured();
    expect(run.firstPositionAfterResume.inMilliseconds, greaterThan(1100));
    expect(run.firstPositionFromZero.inMilliseconds, lessThan(500));
  });

  test('a BACKWARDS seek over HLS lands where it was aimed', () async {
    // Backwards, for M4.R/T2's reason: ordinary playback reaches any forward
    // target on its own, so a `seek()` replaced by a no-op passes a
    // forward-seek assertion. Nothing but a real seek moves position back.
    final run = await _measured();
    expect(run.beforeBackwardSeek.inMilliseconds, greaterThan(2000));
    expect(run.afterBackwardSeek.inMilliseconds, lessThan(900));
  });

  test('completion arrives at the END of the transcoded stream', () async {
    // Both counters are reset immediately before the wait (see `_measure`),
    // which is what makes these two un-fakeable: a constant `completed` would
    // return from ~0.4 s having taken no time (M4.R/T3).
    final run = await _measured();
    expect(run.completedFired, isTrue);
    expect(
      run.positionAtCompletion.inMilliseconds,
      closeTo(run.duration.inMilliseconds, 500),
    );
    expect(run.playedFor, greaterThan(const Duration(seconds: 1)));
  });
}

/// One real HLS playback session, measured once and awaited by every test.
///
/// A memoised Future rather than a `setUpAll`, for M4.R/T4's reason: with the
/// work in `setUpAll` every failure reports as `(setUpAll)` and the file
/// collapses to one result — under one deliberate mutation an M4 run went
/// `+0 -1` and five tests silently did not run.
Future<_Run>? _memo;
Future<_Run> _measured() => _memo ??= _measure();

MediaKitPlaybackHost? _host;

class _Run {
  const _Run({
    required this.duration,
    required this.tracks,
    required this.firstPositionAfterResume,
    required this.firstPositionFromZero,
    required this.beforeBackwardSeek,
    required this.afterBackwardSeek,
    required this.completedFired,
    required this.positionAtCompletion,
    required this.playedFor,
  });

  final Duration duration;
  final PlaybackTracks tracks;
  final Duration firstPositionAfterResume;
  final Duration firstPositionFromZero;
  final Duration beforeBackwardSeek;
  final Duration afterBackwardSeek;
  final bool completedFired;
  final Duration positionAtCompletion;
  final Duration playedFor;
}

Future<_Run> _measure() async {
  HttpOverrides.global = null;
  ensureLibmpv();
  useHeadlessPlayer();

  final api = await liveApi();
  final categories = await api.categories();
  final shows = categories.firstWhere((c) => c.leaf == 'Shows');
  final show = (await api.categoryMedia(shows.id)).single;
  final detail = await api.mediaDetail(show.id);

  // The pre-flight the player runs, against the real server. It must NOT throw
  // here: transcoding is on, so the file route answers 307.
  await api.requirePlayable(detail.id, const FileIndex(0));

  final headers = await api.playbackHeaders();
  final raw = Player();
  final host = MediaKitPlaybackHost(RealMpvPlayer.over(raw));
  _host = host;

  PlaybackRequest request(Duration startAt) => PlaybackRequest(
    // `fileUrl`, so libmpv follows the 307 itself — exactly what production
    // hands it. Nothing here ever names the HLS route.
    url: api.fileUrl(detail.id, const FileIndex(0)),
    headers: headers.headers,
    startAt: startAt,
    verifyTls: false,
  );

  // ---- the resume arm first, so F8's number is taken on a fresh open -------
  final resumePositions = <Duration>[];
  final resumeWatch = host.position.listen(resumePositions.add);
  await host.open(request(const Duration(milliseconds: 1200)));
  await host.play();
  final firstAfterResume = await host.position
      .firstWhere((p) => p > Duration.zero)
      .timeout(const Duration(seconds: 40));
  await host.pause();
  await resumeWatch.cancel();

  // ---- everything else on a second open, from zero ------------------------
  final durationSeen = host.duration.firstWhere((d) => d > Duration.zero);
  final tracksSeen = host.tracks.firstWhere((t) => t.audio.isNotEmpty);
  final fromZero = host.position.firstWhere((p) => p > Duration.zero);
  final completed = host.completed.firstWhere((done) => done);

  var furthest = Duration.zero;
  final watching = host.position.listen((p) {
    if (p > furthest) furthest = p;
  });
  final playing = Stopwatch();

  await host.open(request(Duration.zero));
  await host.play();

  final duration = await durationSeen.timeout(const Duration(seconds: 40));
  final tracks = await tracksSeen.timeout(const Duration(seconds: 40));
  final firstFromZero = await fromZero.timeout(const Duration(seconds: 40));

  final past2s = await host.position
      .firstWhere((p) => p > const Duration(milliseconds: 2000))
      .timeout(const Duration(seconds: 60));
  await host.pause();
  final landedBack = host.position.firstWhere(
    (p) => p < const Duration(milliseconds: 900),
  );
  await host.seek(const Duration(milliseconds: 400));
  final afterBackwardSeek = await landedBack.timeout(
    const Duration(seconds: 30),
  );

  // Both counters restart HERE, immediately before the wait, which is what
  // makes the completion assertions un-fakeable (M4.R/T3).
  furthest = Duration.zero;
  playing
    ..reset()
    ..start();
  await host.play();
  final completedFired = await completed.timeout(const Duration(seconds: 60));
  playing.stop();
  final positionAtCompletion = furthest;
  await watching.cancel();

  return _Run(
    duration: duration,
    tracks: tracks,
    firstPositionAfterResume: firstAfterResume,
    firstPositionFromZero: firstFromZero,
    beforeBackwardSeek: past2s,
    afterBackwardSeek: afterBackwardSeek,
    completedFired: completedFired,
    positionAtCompletion: positionAtCompletion,
    playedFor: playing.elapsed,
  );
}
