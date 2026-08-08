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
  bool transcode = false,
  List<SubtitleInfo> subtitles = const [],
}) => MediaDetail(
  id: _id,
  title: 'Direct Play Movie',
  files: [
    for (var i = 0; i < files; i++)
      FileInfo(
        index: FileIndex(i),
        size: size,
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
  });

  group('NF6 — the lifecycle report is what survives an OS kill', () {
    test('backgrounding pauses and reports', () async {
      final controller = controllerFor();
      await controller.start();
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitPosition(const Duration(seconds: 20))
        ..emitPosition(const Duration(seconds: 25));
      await pumpEventQueue();

      await controller.handleLifecycle(AppLifecycleState.paused);

      expect(host.calls, contains('pause'));
      expect(api.reports.last.event, ProgressEvent.pause);
      expect(api.reports.last.position, 25.0);
    });

    test(
      'resuming does nothing — it must not start playing in a pocket',
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
        ..emitError('Failed to open.')
        ..emitError('Failed to open.')
        ..emitError('Failed to open.');
      await pumpEventQueue();

      expect(api.calls.where((c) => c == 'me'), hasLength(1));
      expect(controller.needsSignIn, isFalse);
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

      expect(controller.needsDetailRefetch, isTrue);
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
