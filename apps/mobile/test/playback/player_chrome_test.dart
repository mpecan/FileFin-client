import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

/// What the player says about itself, and what it does to the device around
/// it. Split from `player_page_test.dart` for `just file-size`'s 600-line hard
/// limit; both groups landed there together and both are about the screen's
/// edges rather than its transport.
void main() {
  const id = MediaId('e4285edb34d5');

  late FakeLibraryApi api;
  late FakePlaybackHost host;
  late FakeNetworkStatus network;

  SavedServer server() => SavedServer(
    id: const ServerId('a'),
    name: 'Attic NAS',
    baseUrl: Uri.parse('http://nas.local'),
  );

  setUp(() {
    api = FakeLibraryApi()
      ..playbackHeadersResult = const PlaybackSessionHeaders({'Cookie': 'x'});
    host = FakePlaybackHost();
    network = FakeNetworkStatus();
  });

  Future<void> pumpPlayer(
    WidgetTester tester, {
    PlayerControlsMetrics metrics = PlayerControlsMetrics.phone,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          api: api,
          hostFactory: () => host,
          nowPlayingFactory: fakeNowPlayingFactory(),
          network: network,
          detail: const MediaDetail(
            id: id,
            title: 'Film',
            files: [FileInfo(name: 'Film', ext: '.mp4')],
          ),
          server: server(),
          prefs: const PlaybackPrefs(),
          initialFile: const FileIndex(0),
          startAt: Duration.zero,
          metrics: metrics,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// `playerFacts` names the file only for a multi-file item, and nothing
  /// covered the single-file side: `just mutants` weakened `> 1` to `>= 1` and
  /// the suite stayed green. With `>=`, a film's facts line carries its own
  /// filename next to the title that is already above it.
  group('the facts line under the title', () {
    PlayerController controllerOver(List<FileInfo> files) {
      final c = PlayerController(
        api: api,
        host: host,
        network: network,
        detail: MediaDetail(id: id, title: 'Film', files: files),
        server: server(),
        prefs: const PlaybackPrefs(),
        initialFile: const FileIndex(0),
        startAt: Duration.zero,
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a single-file item is not told which file it is', () {
      expect(
        playerFacts(
          controllerOver(const [FileInfo(name: 'Woodstock', ext: '.mkv')]),
        ),
        'mkv · direct play',
      );
    });

    test('a multi-file item is', () {
      expect(
        playerFacts(
          controllerOver(const [
            FileInfo(name: 'S1E1', ext: '.mkv'),
            FileInfo(index: FileIndex(1), name: 'S1E2', ext: '.mkv'),
          ]),
        ),
        'S1E1 · mkv · direct play',
      );
    });

    /// The server's own verdict, not a guess from the extension.
    test('a transcoded file says so instead of saying direct play', () {
      expect(
        playerFacts(
          controllerOver(const [
            FileInfo(name: 'Show', ext: '.avi', transcode: true),
          ]),
        ),
        'avi · transcode',
      );
    });
  });

  /// **The orientation lock is a phone thing**, and `just mutants` showed
  /// nothing said so: inverting `metrics == phone` and deleting the `dispose`
  /// release both survived. A television is already landscape and has no
  /// sensor to disagree, so asking it to rotate is a no-op that logs; a phone
  /// that never released the lock would leave every screen after the player
  /// stuck in landscape.
  group('the orientation lock', () {
    late List<MethodCall> platform;

    setUp(() {
      platform = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            platform.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
    });

    List<Object?> orientationsSet() => [
      for (final c in platform)
        if (c.method == 'SystemChrome.setPreferredOrientations')
          (c.arguments as List<Object?>),
    ];

    testWidgets('a phone is locked to the two landscape orientations', (
      tester,
    ) async {
      await pumpPlayer(tester);

      expect(orientationsSet(), [
        [
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ],
      ]);
    });

    testWidgets('a television is not locked at all', (tester) async {
      await pumpPlayer(tester, metrics: PlayerControlsMetrics.tv);

      expect(orientationsSet(), isEmpty);
    });

    testWidgets('leaving the player releases the lock', (tester) async {
      await pumpPlayer(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(orientationsSet().last, isEmpty);
    });
  });
}
