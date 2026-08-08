import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

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

  group('start — F13 samples the network exactly once, before playing', () {
    test('an unmetered connection plays straight away', () async {
      final controller = controllerFor();

      await controller.start();

      expect(network.samples, 1);
      expect(controller.decision, isA<PlayDirect>());
      expect(host.opened, hasLength(1));
      expect(host.calls, contains('play'));
    });

    test('wifi-only over metered refuses, and NOTHING is opened', () async {
      final controller = controllerFor(
        server: SavedServer(
          id: const ServerId('home'),
          name: 'Home',
          baseUrl: Uri.parse('http://nas.local'),
          wifiOnly: true,
        ),
      );
      network.answer = NetworkType.metered;

      await controller.start();

      expect(
        controller.decision,
        isA<Refuse>().having(
          (r) => r.reason,
          'reason',
          RefuseReason.wifiOnlyOnMetered,
        ),
      );
      expect(host.opened, isEmpty);
      expect(api.calls, isNot(contains('playbackHeaders')));
    });

    test('a large file on metered asks first, then plays on confirm', () async {
      final controller = controllerFor(
        detail: _detail(size: 900 * 1000 * 1000),
      );
      network.answer = NetworkType.metered;

      await controller.start();
      expect(
        controller.decision,
        isA<ConfirmLargeOnMetered>().having(
          (c) => c.bytes,
          'bytes',
          900 * 1000 * 1000,
        ),
      );
      expect(host.opened, isEmpty);

      await controller.confirmLargeOnMetered();

      expect(controller.decision, isA<PlayDirect>());
      expect(host.opened, hasLength(1));
    });

    test('confirming when nothing was asked does nothing', () async {
      final controller = controllerFor();
      await controller.start();
      final opens = host.opened.length;

      await controller.confirmLargeOnMetered();

      expect(host.opened, hasLength(opens));
    });

    test('D10 — a pinned server is refused unless allowed for it', () async {
      api.transport = PlaybackTransport.pinnedTls;
      final controller = controllerFor();

      await controller.start();

      expect(
        controller.decision,
        isA<Refuse>().having(
          (r) => r.reason,
          'reason',
          RefuseReason.unverifiablePlaybackTls,
        ),
      );
      expect(host.opened, isEmpty);
    });

    test('D10 — the per-server override lets it through', () async {
      api.transport = PlaybackTransport.pinnedTls;
      final controller = controllerFor(
        server: SavedServer(
          id: const ServerId('home'),
          name: 'Home',
          baseUrl: Uri.parse('https://nas.local'),
          allowUnverifiedPlayback: true,
        ),
      );

      await controller.start();

      expect(controller.decision, isA<PlayDirect>());
      // Verification stays OFF for a pinned certificate: turning it on would
      // refuse the very certificate the user accepted.
      expect(host.opened.single.verifyTls, isFalse);
    });

    test('an OS-trusted server opens with verification ON', () async {
      api.transport = PlaybackTransport.osTrustedTls;
      final controller = controllerFor();

      await controller.start();

      expect(host.opened.single.verifyTls, isTrue);
    });
  });

  group('open — the order is the security property', () {
    test('the cookie is fetched live, immediately before the open', () async {
      final controller = controllerFor(
        detail: _detail(subtitles: const [SubtitleInfo(label: 'English')]),
      );

      await controller.start();

      // `playbackHeaders` FIRST: it is a real authenticated round trip, so F3
      // has renewed a dead session before libmpv — which cannot see a 401 — is
      // handed anything.
      expect(api.calls.first, 'playbackTransport');
      expect(api.calls, contains('playbackHeaders'));
      expect(
        api.calls.indexOf('playbackHeaders'),
        lessThan(api.calls.indexOf('subtitleText(e4285edb34d5, 0, 0)')),
      );
      expect(host.opened.single.headers, {
        'Cookie': 'filefin_session=sess-1',
      });
    });

    test('the url and the start position are the ones asked for', () async {
      final controller = controllerFor(
        initialFile: 1,
        startAt: const Duration(seconds: 42),
        detail: _detail(files: 3),
      );

      await controller.start();

      expect(host.opened.single.url.path, '/api/media/e4285edb34d5/file/1');
      expect(host.opened.single.startAt, const Duration(seconds: 42));
    });

    test('a sidecar is fetched through the API and shown', () async {
      final controller = controllerFor(
        detail: _detail(
          subtitles: const [
            SubtitleInfo(label: 'English'),
          ],
        ),
      );

      await controller.start();

      expect(controller.subtitles.single.label, 'English');
      expect(controller.subtitles.single.data, startsWith('WEBVTT'));
      expect(host.subtitles.single?.label, 'English');
    });

    test('a sidecar that fails to fetch is dropped, not fatal', () async {
      api.subtitleResult = NotFound(_url);
      final controller = controllerFor(
        detail: _detail(subtitles: const [SubtitleInfo(label: 'English')]),
      );

      await controller.start();

      expect(controller.subtitles, isEmpty);
      expect(controller.failure, isNull);
      expect(host.opened, hasLength(1));
    });

    test(
      'a dead session that cannot be renewed says so and asks for a sign-in',
      () async {
        api.playbackHeadersResult = SessionExpired(_url);
        final controller = controllerFor();

        await controller.start();

        expect(controller.failure, contains('session'));
        expect(controller.needsSignIn, isTrue);
        expect(host.opened, isEmpty);
      },
    );
  });

  group('triggers — every report is keyed on the file that is playing', () {
    Future<PlayerController> playing({int files = 1}) async {
      final controller = controllerFor(detail: _detail(files: files));
      await controller.start();
      host.emitDuration(const Duration(seconds: 100));
      await pumpEventQueue();
      return controller;
    }

    test('a position tick reports a checkpoint', () async {
      final controller = await playing();

      host.emitPosition(const Duration(seconds: 40));
      await pumpEventQueue();

      expect(controller.position, const Duration(seconds: 40));
      expect(api.reports.single.event, ProgressEvent.checkpoint);
      expect(api.reports.single.position, 40.0);
    });

    test('playing false reports a pause', () async {
      final controller = await playing();
      host
        ..emitPosition(const Duration(seconds: 40))
        // A second tick inside the interval sends nothing, so the pause below
        // is the first report of second 45 — which is the case that matters,
        // because a pause at a second the server already has carries nothing.
        ..emitPosition(const Duration(seconds: 45));
      await pumpEventQueue();

      host.emitPlaying(value: false);
      await pumpEventQueue();

      expect(controller.playing, isFalse);
      expect(api.reports.last.event, ProgressEvent.pause);
    });

    test('a terminal event at a second already reported is skipped', () async {
      // Rule 3 of the progress policy, seen through the controller: a pause at
      // the exact second the last checkpoint carried tells the server nothing
      // it does not already hold.
      final controller = await playing();
      host.emitPosition(const Duration(seconds: 40));
      await pumpEventQueue();

      await controller.close();

      expect(api.reports, hasLength(1));
      expect(api.reports.single.event, ProgressEvent.checkpoint);
    });

    test('a seek reports at the position it landed on', () async {
      final controller = await playing();

      await controller.seekTo(const Duration(seconds: 55));

      expect(host.seeks, [const Duration(seconds: 55)]);
      expect(api.reports.last.event, ProgressEvent.seek);
      expect(api.reports.last.position, 55.0);
    });

    test('completion reports at the DURATION, not the last tick', () async {
      // mpv's final position tick can land milliseconds short of the end,
      // which on a short file is below the 90% threshold — so the crossing
      // would be missed and the item never marked watched.
      final controller = await playing();
      host.emitPosition(const Duration(seconds: 89));
      await pumpEventQueue();

      host.emitCompleted();
      await pumpEventQueue();

      expect(api.reports.last.event, ProgressEvent.ended);
      expect(api.reports.last.position, 100.0);
      expect(controller.watchState.watched, isTrue);
    });

    test('closing the route reports a stop, awaited', () async {
      final controller = await playing();
      host
        ..emitPosition(const Duration(seconds: 40))
        ..emitPosition(const Duration(seconds: 45));
      await pumpEventQueue();

      await controller.close();

      expect(api.reports.last.event, ProgressEvent.stop);
    });
  });
}
