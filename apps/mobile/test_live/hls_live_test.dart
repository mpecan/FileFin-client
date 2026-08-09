@Timeout(Duration(seconds: 180))
library;

import 'dart:async';
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
    // **Not the cookie proof, and it used to say it was.** Removing the header
    // does not fail this assertion — `_measure` dies forty seconds earlier and
    // `expect` never evaluates — and the number is a *playlist* fact anyway:
    // mpv takes 3.023 from `#EXTINF:3.023` rather than from the 3.000 s
    // source (M5.0/E-C). The cookie's falsifiable test is
    // `hls_no_cookie_test.dart`; the segments' evidence is position and
    // completion, below.
    //
    // What this does pin is that the 90% crossing is computed against
    // whatever mpv says, which is the playlist's number and not the file's.
    final run = await _measured();
    expect(run.duration.inMilliseconds, greaterThan(2900));
    expect(run.duration.inMilliseconds, lessThan(3200));
  });

  test('the transcoded stream carries an audio track (F7)', () async {
    final run = await _measured();
    // `hasLength(1)`, not `isNotEmpty`: the wait predicate is already
    // `t.audio.isNotEmpty`, so restating it here could not fail — an empty
    // list hangs rather than reddens. The seeded HEVC item has exactly one
    // audio track.
    expect(run.tracks.audio, hasLength(1));
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
    //
    // **This is also the segment evidence.** Reaching the end of the stream
    // means mpv fetched the playlist AND every segment, and both routes sit
    // behind `s.auth` (`server.go:283`) — a cookie that did not survive the
    // 307 stops playback dead rather than shortening it.
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

  // Production's own sequence, reproduced in order rather than asserted on:
  // `PlayerController._open` runs this before it touches the engine, so a run
  // that skipped it would not be measuring what the player does. It carries no
  // expectation of its own — the 307's coverage is in `preflight_test.dart`
  // and the `filefin_api` integration suite, which assert on the status.
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
  await host.open(request(const Duration(milliseconds: 1200)));
  await host.play();
  final pending = <StreamSubscription<Object?>>[];

  /// `firstWhere`, but over a subscription this function can still cancel.
  ///
  /// `Stream.firstWhere` keeps a listener alive until its predicate matches,
  /// and nothing can reach it to stop it — so a run that threw before the wait
  /// completed left listeners on an mpv context `tearDownAll` was about to
  /// dispose, which is exactly the condition M4.R/T4 named as the
  /// `flutter_tester` SIGBUS. Measured under one deliberate mutation here.
  Future<T> first<T>(Stream<T> stream, bool Function(T) matches) {
    final answer = Completer<T>();
    late StreamSubscription<T> sub;
    sub = stream.listen((value) {
      if (answer.isCompleted || !matches(value)) return;
      answer.complete(value);
    });
    pending.add(sub);
    return answer.future;
  }

  final firstAfterResume = await _stage(
    'first position after resume',
    first<Duration>(host.position, (p) => p > Duration.zero),
    _long,
  );
  await host.pause();

  // ---- everything else on a second open, from zero ------------------------
  final durationSeen = first<Duration>(host.duration, (d) => d > Duration.zero);
  final tracksSeen = first<PlaybackTracks>(
    host.tracks,
    (t) => t.audio.isNotEmpty,
  );
  final fromZero = first<Duration>(host.position, (p) => p > Duration.zero);
  final completed = first<bool>(host.completed, (done) => done);

  var furthest = Duration.zero;
  pending.add(
    host.position.listen((p) {
      if (p > furthest) furthest = p;
    }),
  );
  final playing = Stopwatch();

  try {
    await host.open(request(Duration.zero));
    await host.play();

    final duration = await _stage('duration', durationSeen, _long);
    final tracks = await _stage('audio tracks', tracksSeen, _long);
    final firstFromZero = await _stage(
      'first position from zero',
      fromZero,
      _long,
    );

    final past2s = await _stage(
      'position past 2 s',
      first<Duration>(
        host.position,
        (p) => p > const Duration(milliseconds: 2000),
      ),
      const Duration(seconds: 60),
    );
    await host.pause();
    final landedBack = first<Duration>(
      host.position,
      (p) => p < const Duration(milliseconds: 900),
    );
    await host.seek(const Duration(milliseconds: 400));
    final afterBackwardSeek = await _stage(
      'backwards seek landing',
      landedBack,
      const Duration(seconds: 30),
    );

    // Both counters restart HERE, immediately before the wait, which is what
    // makes the completion assertions un-fakeable (M4.R/T3).
    furthest = Duration.zero;
    playing
      ..reset()
      ..start();
    await host.play();
    final completedFired = await _stage(
      'completion',
      completed,
      const Duration(seconds: 60),
    );
    playing.stop();

    return _Run(
      duration: duration,
      tracks: tracks,
      firstPositionAfterResume: firstAfterResume,
      firstPositionFromZero: firstFromZero,
      beforeBackwardSeek: past2s,
      afterBackwardSeek: afterBackwardSeek,
      completedFired: completedFired,
      positionAtCompletion: furthest,
      playedFor: playing.elapsed,
    );
  } finally {
    // Every listener this function ever registered, on the failure path too.
    for (final sub in pending) {
      await sub.cancel();
    }
  }
}

/// The wait most stages get. One name, so a change is one edit.
const _long = Duration(seconds: 40);

/// [future], bounded, and **named** so a timeout says which stage died.
///
/// Without this every one of the five tests reported the same bare
/// `TimeoutException` whatever had actually broken, because they all await one
/// memoised measurement.
Future<T> _stage<T>(String name, Future<T> future, Duration limit) =>
    future.timeout(
      limit,
      onTimeout: () => throw TimeoutException('HLS stage: $name'),
    );
