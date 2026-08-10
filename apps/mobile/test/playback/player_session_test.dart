import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/progress_reporter.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

/// The second half of `player_controller_test.dart`: what happens AFTER a
/// file is playing — advancing, backgrounding, recovering and closing.
///
/// Split because the one file crossed `file-size`'s 400-line soft warning,
/// and a gate warning may fall or hold and never rise.
///
/// A `NetworkStatus` a test can set.
final class FakeNetwork extends NetworkStatus {
  FakeNetwork(this.answer);

  NetworkType answer;
  int samples = 0;

  @override
  Future<NetworkType> current() async {
    samples++;
    return answer;
  }
}

const _id = MediaId('e4285edb34d5');
final Uri _url = Uri.parse(
  'http://nas.local/api/media/e4285edb34d5/file/0',
);

MediaDetail _detail({
  int files = 1,
  int size = 10,
  List<int>? sizes,
  bool transcode = false,
  List<SubtitleInfo> subtitles = const [],
}) => MediaDetail(
  id: _id,
  title: 'Direct Play Movie',
  files: [
    for (var i = 0; i < files; i++)
      FileInfo(
        index: FileIndex(i),
        size: sizes == null ? size : sizes[i],
        transcode: transcode,
        subtitles: i == 0 ? subtitles : const [],
      ),
  ],
);

void main() {
  late FakeLibraryApi api;
  late FakePlaybackHost host;
  late FakeNetwork network;

  setUp(() {
    api = FakeLibraryApi()
      ..playbackHeadersResult = const PlaybackSessionHeaders({
        'Cookie': 'filefin_session=sess-1',
      })
      ..subtitleResult = 'WEBVTT\n\n00:00.000 --> 00:02.000\nHello\n'
      ..meResult = const AuthResult(user: 'sam');
    host = FakePlaybackHost();
    network = FakeNetwork(NetworkType.wifi);
  });

  PlayerController controllerFor({
    MediaDetail? detail,
    SavedServer? server,
    PlaybackPrefs prefs = const PlaybackPrefs(),
    int initialFile = 0,
    Duration startAt = Duration.zero,
  }) {
    final controller = PlayerController(
      api: api,
      host: host,
      network: network,
      detail: detail ?? _detail(),
      server:
          server ??
          SavedServer(
            id: const ServerId('home'),
            name: 'Home',
            baseUrl: Uri.parse('http://nas.local'),
          ),
      prefs: prefs,
      initialFile: FileIndex(initialFile),
      startAt: startAt,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('next-file (F7) — we advance, mpv does not', () {
    test('Next stops the old file, opens the next one at zero', () async {
      final controller = controllerFor(detail: _detail(files: 2));
      await controller.start();
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitPosition(const Duration(seconds: 40))
        ..emitPosition(const Duration(seconds: 45));
      await pumpEventQueue();

      await controller.next();

      expect(api.reports.map((r) => r.event), contains(ProgressEvent.stop));
      expect(controller.current, const FileIndex(1));
      expect(host.opened.last.url.path, '/api/media/e4285edb34d5/file/1');
      expect(host.opened.last.startAt, Duration.zero);
    });

    test('there is no Next on the last file', () async {
      final controller = controllerFor();
      await controller.start();

      expect(controller.hasNext, isFalse);
      await controller.next();

      expect(host.opened, hasLength(1));
    });

    test('the old position is never posted under the new file', () async {
      // M4.R/P1, and it was user-visible data corruption. Against real libmpv
      // the first event after a second `open()` is deterministically
      // `playing=false`, BEFORE any position or duration event:
      //   playing=false / position=0 / duration=0 / playing=true / duration=3s
      // With `_position` still holding the finished file's 2.9 s that pause was
      // posted as `{"file":1,"position":2.9,"duration":3}` — 2.9/3.0 is past
      // the 0.90 threshold on the LAST file, so tapping Next at the end of
      // episode 1 marked the whole show watched. Replayed against a real
      // v0.20.3 server: `VIEW watched=True perFile=[True, True]`.
      final controller = controllerFor(detail: _detail(files: 2));
      await controller.start();
      host
        ..emitDuration(const Duration(seconds: 3))
        ..emitPosition(const Duration(milliseconds: 2900));
      await pumpEventQueue();

      await controller.next();
      host.emitPlaying(value: false);
      await pumpEventQueue();

      expect(controller.outcome.state.watched, isFalse);
      expect(
        api.reports.where((r) => r.file == const FileIndex(1)),
        isEmpty,
        reason: 'nothing describes a file that has not reported a tick yet',
      );
      expect(controller.position, Duration.zero);
      expect(controller.duration, Duration.zero);
    });

    test('a duration alone does not say where the new file is', () async {
      // Zeroing the two fields is necessary and NOT sufficient. mpv reports the
      // new file's length while loading it, and `playing == false` still
      // arrives before the first position tick — so without the suppression
      // this posts `{"file":1,"position":0,"duration":100}`, a claim about a
      // file nothing has measured that overwrites the pointer the server holds.
      final controller = controllerFor(detail: _detail(files: 2));
      await controller.start();
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitPosition(const Duration(seconds: 40));
      await pumpEventQueue();

      await controller.next();
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitPlaying(value: false);
      await pumpEventQueue();

      expect(api.reports.where((r) => r.file == const FileIndex(1)), isEmpty);
    });

    test('the new file reports normally once it has ticked', () async {
      // The other direction of the guard above: suppressing the pause until a
      // tick arrives must not suppress it for the file's whole life.
      final controller = controllerFor(detail: _detail(files: 2));
      await controller.start();
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitPosition(const Duration(seconds: 40));
      await pumpEventQueue();

      await controller.next();
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitPosition(const Duration(seconds: 5))
        // Inside the interval, so it sends nothing — which makes the pause
        // below the first report of second 6, the case that matters.
        ..emitPosition(const Duration(seconds: 6));
      await pumpEventQueue();

      host.emitPlaying(value: false);
      await pumpEventQueue();

      expect(api.reports.last.event, ProgressEvent.pause);
      expect(api.reports.last.file, const FileIndex(1));
      expect(api.reports.last.position, 6.0);
    });

    test('F13 is asked again for a file with its own size', () async {
      // M4.R/P4: `next()` went straight to `_open()`, so F13 saw the FIRST
      // file and no other. Measured with a 10-byte episode 1 and a 9 GiB
      // episode 2 on a metered connection — file 1 opened with no prompt.
      final controller = controllerFor(
        detail: _detail(files: 2, sizes: [10, 900 * 1000 * 1000]),
      );
      network.answer = NetworkType.metered;

      await controller.start();
      expect(controller.decision, isA<PlayDirect>());

      await controller.next();

      expect(
        controller.decision,
        isA<ConfirmLargeOnMetered>().having(
          (c) => c.bytes,
          'bytes',
          900 * 1000 * 1000,
        ),
      );
      expect(host.opened, hasLength(1), reason: 'the big file waits');
      // The sample stays once-per-session; only the DECISION is re-taken.
      expect(network.samples, 1);

      await controller.confirmLargeOnMetered();

      expect(host.opened.last.url.path, '/api/media/e4285edb34d5/file/1');
    });
  });

  group('NF6 and F14 — the lifecycle report, and the pause that is gone', () {
    test('backgrounding reports and does NOT pause (F14)', () async {
      // **This assertion is inverted from what it said until M7.6, and the
      // inversion is the feature.** The report still has to happen: it is the
      // only thing that runs before an OS kill, so it is what the user comes
      // back to. The pause used to happen alongside it, and F14 is the
      // requirement that it must not — a lock-screen transport over a player
      // that stops the moment the screen locks is a control for nothing.
      final controller = controllerFor();
      await controller.start();
      final pausesBefore = host.calls.where((c) => c == 'pause').length;
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitPosition(const Duration(seconds: 20))
        ..emitPosition(const Duration(seconds: 25));
      await pumpEventQueue();

      await controller.handleLifecycle(AppLifecycleState.paused);

      expect(host.calls.where((c) => c == 'pause'), hasLength(pausesBefore));
      expect(api.reports.last.event, ProgressEvent.pause);
      expect(api.reports.last.position, 25.0);
    });

    test(
      'resuming does nothing — the engine never stopped',
      () async {
        final controller = controllerFor();
        await controller.start();
        final before = host.calls.length;

        await controller.handleLifecycle(AppLifecycleState.resumed);

        expect(host.calls, hasLength(before));
      },
    );
  });

  group('playback-level 401 — mpv has no status code, so we ask', () {
    test(
      'a live session means the file was the problem, and it retries once',
      () async {
        final controller = controllerFor();
        await controller.start();
        host
          ..emitDuration(const Duration(seconds: 100))
          ..emitPosition(const Duration(seconds: 30));
        await pumpEventQueue();

        host.emitError('Failed to open http://nas.local/f.');
        await pumpEventQueue();

        expect(api.calls, contains('me'));
        // Re-opened at the last position, not from the beginning.
        expect(host.opened.last.startAt, const Duration(seconds: 30));
        expect(controller.needsSignIn, isFalse);
      },
    );

    test('it re-opens at most once, so a broken file cannot loop', () async {
      final controller = controllerFor();
      await controller.start();
      await pumpEventQueue();

      host
        ..emitError('Failed to open http://nas.local/f: 404 Not Found.')
        ..emitError('Failed to open http://nas.local/f: 404 Not Found.')
        ..emitError('Failed to open http://nas.local/f: 404 Not Found.');
      await pumpEventQueue();

      expect(api.calls.where((c) => c == 'me'), hasLength(1));
      expect(controller.needsSignIn, isFalse);
      // F12: mpv's own words reach the screen. Before M4.R/P2 `message` was
      // never read at all, so a broken file left a black player saying
      // nothing whatever.
      expect(controller.failure, contains('404 Not Found'));
    });

    test("a retry before the first tick keeps F8's resume offset", () async {
      // `_startAt = _position` with no tick yet threw away the offset the
      // detail screen resumed from and restarted the film (M4.R/P2).
      final controller = controllerFor(startAt: const Duration(seconds: 42));
      await controller.start();

      host.emitError('Failed to open.');
      await pumpEventQueue();

      expect(host.opened.last.startAt, const Duration(seconds: 42));
    });

    test('a dead session routes to sign-in rather than retrying', () async {
      final controller = controllerFor();
      await controller.start();
      api.meResult = SessionExpired(_url);

      host.emitError('Failed to open.');
      await pumpEventQueue();

      expect(controller.needsSignIn, isTrue);
      expect(controller.failure, isNotNull);
    });

    test('a session dying AFTER an earlier error still signs in', () async {
      // M4.R/P2's second half: the guard latched for the controller's whole
      // life, so one transient error anywhere earlier meant a session that
      // died mid-film never reached `me()` again and never routed to sign-in.
      final controller = controllerFor();
      await controller.start();
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitError('Failed to open.');
      await pumpEventQueue();
      expect(controller.needsSignIn, isFalse);

      // Playback resumed: the retry is no longer spent.
      host.emitPosition(const Duration(seconds: 30));
      await pumpEventQueue();

      api.meResult = SessionExpired(_url);
      host.emitError('Failed to open.');
      await pumpEventQueue();

      expect(controller.needsSignIn, isTrue);
      expect(api.calls.where((c) => c == 'me'), hasLength(2));
    });
  });

  group('progress reporting is surfaced, never fatal', () {
    test('a rejected report stops reporting and is visible', () async {
      final controller = controllerFor();
      await controller.start();
      host.emitDuration(const Duration(seconds: 100));
      api.progressResult = BadRequest(_url, 'bad file index');

      host.emitPosition(const Duration(seconds: 40));
      await pumpEventQueue();

      expect(controller.reportStop, ReportStop.rejected);
      // Playback is untouched: a failed report is a fact about the network,
      // not about the film.
      expect(host.calls, isNot(contains('pause')));
    });

    test('a single-file crossing latches the refetch flag', () async {
      final controller = controllerFor();
      await controller.start();
      host.emitDuration(const Duration(seconds: 100));
      await pumpEventQueue();

      host.emitCompleted();
      await pumpEventQueue();

      expect(controller.outcome.needsDetailRefetch, isTrue);
    });
  });

  test('dispose fires a final report and always disposes the host', () async {
    final controller = controllerFor();
    await controller.start();
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 12))
      ..emitPosition(const Duration(seconds: 18));
    await pumpEventQueue();

    controller.dispose();
    await pumpEventQueue();

    expect(host.disposed, isTrue);
    expect(api.reports.last.event, ProgressEvent.stop);
  });
}
