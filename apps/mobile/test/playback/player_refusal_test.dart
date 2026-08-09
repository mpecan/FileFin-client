import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

const _id = MediaId('919ac9caad25');

MediaDetail _show() => MediaDetail(
  id: _id,
  title: 'Transcode Show',
  files: [
    for (var i = 0; i < 2; i++)
      FileInfo(index: FileIndex(i), size: 10, transcode: true),
  ],
);

/// An open that fails [failures] times and then works, so the bound on the
/// pre-flight's retry can be measured rather than assumed.
final class _FlakyApi extends FakeLibraryApi {
  _FlakyApi(this.failure, {required this.failures});

  final FileFinApiException failure;
  int failures;

  @override
  Future<void> requirePlayable(
    MediaId id,
    FileIndex file, {
    CancelToken? cancelToken,
  }) async {
    requirePlayableResult = failures > 0 ? failure : null;
    if (failures > 0) failures--;
    return super.requirePlayable(id, file, cancelToken: cancelToken);
  }
}

/// A pre-flight that never finishes until [gate] is completed.
final class _SlowApi extends FakeLibraryApi {
  final gate = Completer<void>();

  @override
  Future<void> requirePlayable(
    MediaId id,
    FileIndex file, {
    CancelToken? cancelToken,
  }) async {
    await super.requirePlayable(id, file, cancelToken: cancelToken);
    await gate.future;
  }
}

/// What happens to the file the engine is **still holding** when the next
/// one's open never reaches it.
///
/// Its own file rather than more cases in `player_transcoding_test.dart`,
/// which is at 338 lines against a 400-line soft warning whose count may fall
/// or hold and never rise.
///
/// The defect these pin was live at M5 and is M4.R/P1's data corruption
/// returning by a second route: `next()` moves `_current` *before* `_open()`,
/// so a refused pre-flight leaves the engine playing file 0 while every
/// listener writes its events under file 1. The report was blocked only by
/// `decideReport`'s unrelated `duration <= 0 → notStarted`, and one re-emitted
/// duration event walked straight past it.
void main() {
  final url = Uri.parse('https://media.example/api/media/abc/file/1');

  late FakeLibraryApi api;
  late FakePlaybackHost host;

  PlayerController controllerFor(FakeLibraryApi withApi) {
    final controller = PlayerController(
      api: withApi,
      host: host,
      network: FakeNetworkStatus(),
      detail: _show(),
      server: SavedServer(
        id: const ServerId('home'),
        name: 'Home',
        baseUrl: Uri.parse('http://nas.local'),
      ),
      prefs: const PlaybackPrefs(),
      initialFile: const FileIndex(0),
      startAt: Duration.zero,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  FakeLibraryApi freshApi() => FakeLibraryApi()
    ..playbackHeadersResult = const PlaybackSessionHeaders({
      'Cookie': 'filefin_session=sess-1',
    })
    ..meResult = const AuthResult(user: 'sam');

  setUp(() {
    api = freshApi();
    host = FakePlaybackHost();
  });

  /// File 0 playing at 40 s of 100, then `next()` refused by the pre-flight.
  Future<PlayerController> refusedNext() async {
    final controller = controllerFor(api);
    await controller.start();
    host
      ..emitPlaying(value: true)
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 40));
    await pumpEventQueue();
    api.reports.clear();

    api.requirePlayableResult = TranscodingDisabled(url);
    await controller.next();
    return controller;
  }

  group('a refused next() leaves the engine holding the OLD file', () {
    test(
      'and nothing the old file does is posted under the new index',
      () async {
        final controller = await refusedNext();
        expect(controller.current.value, 1, reason: 'the pointer did advance');

        // Exactly the sequence file 0 produces as it runs to its end. The
        // duration re-emit is what made this corrupt at M5: without the
        // identity guard it refills `_duration` and re-arms `decideReport`.
        host.emitPosition(const Duration(seconds: 43));
        await pumpEventQueue();
        host.emitDuration(const Duration(seconds: 100));
        await pumpEventQueue();
        host.emitPosition(const Duration(seconds: 44));
        await pumpEventQueue();
        host.emitCompleted();
        await pumpEventQueue();

        expect(api.reports, isEmpty);
      },
    );

    test('so no ended report ever marks the unopened file watched', () async {
      final controller = await refusedNext();

      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitCompleted();
      await pumpEventQueue();

      expect(
        api.reports.where((r) => r.event == ProgressEvent.ended),
        isEmpty,
        reason: 'an episode nobody opened would be marked fully watched',
      );
      expect(controller.duration, Duration.zero);
    });

    test('and the engine is PAUSED rather than left audible', () async {
      await refusedNext();

      expect(host.calls, contains('pause'));
    });

    test('so a later recovery reopens the new file at ZERO', () async {
      // The old file's playhead poisoning F8's resume offset for a file that
      // was never opened: `opens=[…/file/0@0ms, …/file/1@2400ms]`.
      final controller = await refusedNext();
      host.emitPosition(const Duration(milliseconds: 2400));
      await pumpEventQueue();

      api.requirePlayableResult = null;
      host.emitError('Failed to open http://nas.local/…/file/0.');
      await pumpEventQueue();

      expect(controller.unplayable, isNull);
      expect(host.opened, hasLength(2));
      expect(host.opened.last.url.path, endsWith('/file/1'));
      expect(host.opened.last.startAt, Duration.zero);
    });
  });

  group('a transient pre-flight failure is retried, once', () {
    test('a blip on the first open does not dead-end the player', () async {
      final flaky = _FlakyApi(ConnectionFailed(url), failures: 1)
        ..playbackHeadersResult = const PlaybackSessionHeaders({
          'Cookie': 'filefin_session=sess-1',
        })
        ..meResult = const AuthResult(user: 'sam');
      final controller = controllerFor(flaky);

      await controller.start();

      expect(
        flaky.calls.where((c) => c.startsWith('requirePlayable')),
        hasLength(2),
      );
      expect(host.opened, hasLength(1));
      expect(controller.failure, isNull);
    });

    test('a pre-flight that keeps failing stops at one retry', () async {
      final flaky = _FlakyApi(ConnectionFailed(url), failures: 99)
        ..playbackHeadersResult = const PlaybackSessionHeaders({
          'Cookie': 'filefin_session=sess-1',
        })
        ..meResult = const AuthResult(user: 'sam');
      final controller = controllerFor(flaky);

      await controller.start();

      expect(
        flaky.calls.where((c) => c.startsWith('requirePlayable')),
        hasLength(2),
        reason: 'the bound is one retry, not none and not a loop',
      );
      expect(host.opened, isEmpty);
      expect(controller.failure, isNotNull);
    });

    test('a recovery that already spent the retry does not spend a '
        'second', () async {
      // `_recover` and `_open` share one latch, and this is the interaction
      // that says so: the engine error spends it, and the pre-flight failure
      // that follows must NOT get one of its own. Without the shared latch the
      // pre-flight is asked three times rather than twice.
      final flaky = _FlakyApi(ConnectionFailed(url), failures: 0)
        ..playbackHeadersResult = const PlaybackSessionHeaders({
          'Cookie': 'filefin_session=sess-1',
        })
        ..meResult = const AuthResult(user: 'sam');
      final controller = controllerFor(flaky);
      await controller.start();
      expect(host.opened, hasLength(1));

      flaky.failures = 99;
      host.emitError('Failed to open http://nas.local/…/file/0.');
      await pumpEventQueue();

      expect(
        flaky.calls.where((c) => c.startsWith('requirePlayable')),
        hasLength(2),
        reason: 'start + the one re-open _recover spent; not a third',
      );
      expect(controller.failure, isNotNull);
    });

    test('a 415 is permanent and is NOT retried', () async {
      // The other side of the boundary: re-asking a deterministic refusal
      // spends a round trip to be told the same thing.
      api.requirePlayableResult = TranscodingDisabled(url);
      final controller = controllerFor(api);

      await controller.start();

      expect(
        api.calls.where((c) => c.startsWith('requirePlayable')),
        hasLength(1),
      );
      expect(controller.unplayable, isNotNull);
      // The other side of the pause guard: nothing was ever opened, so there
      // is no engine to silence and no call to make.
      expect(host.calls, isEmpty);
    });
  });

  group('backing out while the pre-flight is in flight (NF5)', () {
    test('nothing is opened on an engine dispose has already torn '
        'down', () async {
      // Measured before the fix: `after gate: opened=1 calls=[dispose, '
      // open(…), play]` — `host.open` on a disposed `Player`. The pre-flight
      // is what made the window worth closing; it is a whole round trip wide.
      final slow = _SlowApi()
        ..playbackHeadersResult = const PlaybackSessionHeaders({
          'Cookie': 'filefin_session=sess-1',
        })
        ..meResult = const AuthResult(user: 'sam');
      final controller = controllerFor(slow);

      final started = controller.start();
      // Pumped, so the pre-flight is genuinely IN FLIGHT rather than not yet
      // reached — without this the test passes for the wrong reason.
      await pumpEventQueue();
      expect(
        slow.calls.where((c) => c.startsWith('requirePlayable')),
        hasLength(1),
      );

      controller.dispose();
      slow.gate.complete();
      await started;

      expect(host.opened, isEmpty);
      expect(host.calls, isNot(anyElement(startsWith('open('))));
    });

    test('every request the open makes carries the token', () async {
      // `whereType<CancelToken>()` above filters nulls out, so a call that
      // silently stopped passing one would survive the assertions in this
      // group. This is the one that notices: all three requests `_open` makes
      // — the pre-flight, the headers and each sidecar — are recorded with a
      // token or this fails.
      api.subtitleResult = 'WEBVTT';
      final controller = PlayerController(
        api: api,
        host: host,
        network: FakeNetworkStatus(),
        detail: const MediaDetail(
          id: _id,
          title: 'Transcode Show',
          files: [
            FileInfo(
              size: 10,
              transcode: true,
              subtitles: [SubtitleInfo(label: 'English')],
            ),
          ],
        ),
        server: SavedServer(
          id: const ServerId('home'),
          name: 'Home',
          baseUrl: Uri.parse('http://nas.local'),
        ),
        prefs: const PlaybackPrefs(),
        initialFile: const FileIndex(0),
        startAt: Duration.zero,
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(api.calls, contains('requirePlayable(919ac9caad25, 0)'));
      expect(api.calls, contains('playbackHeaders'));
      expect(api.calls, contains('subtitleText(919ac9caad25, 0, 0)'));
      expect(api.tokens, everyElement(isNotNull));
    });

    test(
      'and the request itself was cancelled rather than left running',
      () async {
        final slow = _SlowApi()
          ..playbackHeadersResult = const PlaybackSessionHeaders({
            'Cookie': 'filefin_session=sess-1',
          })
          ..meResult = const AuthResult(user: 'sam');
        final controller = controllerFor(slow);

        final started = controller.start();
        await pumpEventQueue();
        // The token reached the API before dispose, and is cancelled after it.
        expect(slow.tokens.whereType<CancelToken>(), isNotEmpty);
        expect(
          slow.tokens.whereType<CancelToken>().every((t) => t.isCancelled),
          isFalse,
          reason: 'nothing is cancelled while the screen is still there',
        );

        controller.dispose();
        slow.gate.complete();
        await started;

        expect(
          slow.tokens.whereType<CancelToken>().every((t) => t.isCancelled),
          isTrue,
        );
      },
    );
  });
}
