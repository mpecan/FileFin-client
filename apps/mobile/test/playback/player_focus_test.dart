import 'package:dpad/dpad.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dpad.dart';
import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

/// Who may take focus on the player screen, and who may not.
///
/// Split from `player_page_test.dart` for `just file-size`'s 600-line hard
/// limit, which those two cases crossed. They belong together anyway: both are
/// about the one thing a television user loses completely when it goes wrong.
void main() {
  const id = MediaId('e4285edb34d5');

  late FakeLibraryApi api;
  late FakePlaybackHost host;

  setUp(() {
    api = FakeLibraryApi()
      ..playbackHeadersResult = const PlaybackSessionHeaders({'Cookie': 'x'});
    host = FakePlaybackHost()
      ..surface = const Focus(
        autofocus: true,
        child: Text('VIDEO', textDirection: TextDirection.ltr),
      );
  });

  Future<void> show(
    WidgetTester tester, {
    PlayerControlsMetrics metrics = PlayerControlsMetrics.phone,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: fileFinTheme(FileFinPalette.dark),
        builder: Dpad.wrap(),
        home: PlayerPage(
          api: api,
          hostFactory: () => host,
          nowPlayingFactory: fakeNowPlayingFactory(),
          network: FakeNetworkStatus(),
          detail: const MediaDetail(
            id: id,
            title: 'Fawlty Towers',
            files: [FileInfo(name: 'S1E1', ext: '.avi')],
          ),
          server: SavedServer(
            id: const ServerId('a'),
            name: 'Attic NAS',
            baseUrl: Uri.parse('http://nas.local'),
          ),
          prefs: const PlaybackPrefs(),
          initialFile: const FileIndex(0),
          startAt: Duration.zero,
          metrics: metrics,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// **The video surface must not be a D-pad target, and this is a
  /// regression.** `1b48603` wrapped it in `ExcludeFocus` inside the overlay
  /// that `RealMpvPlayer.buildSurface` used to build; deleting that class to
  /// make `PlayerControls` the one set of controls took the `ExcludeFocus`
  /// with it. On a television the texture then takes focus and the remote
  /// stops reaching any control at all — measured on a Google TV Streamer,
  /// not inferred.
  testWidgets('the video surface is excluded from focus traversal', (
    tester,
  ) async {
    await show(tester);

    expect(
      find.ancestor(
        of: find.text('VIDEO'),
        matching: find.byType(ExcludeFocus),
      ),
      findsOneWidget,
    );
  });

  /// The behaviour the structural assertion stands for: a remote that presses
  /// nothing but arrows reaches the controls and never the picture.
  testWidgets('a D-pad walk reaches the controls, never the video', (
    tester,
  ) async {
    await show(tester, metrics: PlayerControlsMetrics.tv);

    final reached = await dpadReachable(tester);

    expect(reached, isNot(contains('VIDEO')));
    expect(reached, containsAll(['Play', 'Lock controls']));
  });
}
