import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/browse/library_shell.dart';
import 'package:filefin_mobile/src/playback/playback_settings_sheet.dart';
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:filefin_mobile/src/shell/form_factor.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/tv/tv_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/dpad.dart';
import 'support/fakes.dart';
import 'support/library_header.dart';

/// The one decision `main()`'s form-factor probe actually buys: which shell a
/// signed-in server opens into, and which ramp it is drawn in.
void main() {
  late Directory dir;
  late FakeLibraryApi api;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-formfactor-');
    addTearDown(() => dir.deleteSync(recursive: true));
    api = FakeLibraryApi()
      ..posterResult = null
      ..homeResult = const HomeRows()
      ..restoreResult = null;
    File('${dir.path}/settings.json').writeAsStringSync(
      '{"servers":[{"id":"a","name":"Attic NAS", '
      '"baseUrl":"http://nas.local","lastUser":"sam","authMode":"password",'
      '"wifiOnly":false,"allowUnverifiedPlayback":false}],'
      '"playback":{"progressIntervalSecs":30,"meteredWarnBytes":500000000},'
      '"selectedServerId":"a"}',
    );
  });

  Future<void> launch(WidgetTester tester, FormFactor formFactor) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      FileFinScope(
        dependencies: AppDependencies(
          settings: SettingsStore(dir),
          secrets: InMemorySecretStore(),
          network: FakeNetworkStatus(),
          playbackHostFactory: fakeHostFactory(),
          nowPlayingFactory: fakeNowPlayingFactory(),
          apiFactory: (server, {pin}) => api,
        ),
        child: FileFinApp(formFactor: formFactor),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a phone signs in to the phone shell', (tester) async {
    await launch(tester, FormFactor.phone);

    expect(find.byType(LibraryShell), findsOneWidget);
    expect(find.byType(TvShell), findsNothing);
  });

  testWidgets('a television signs in to the TV shell', (tester) async {
    await launch(tester, FormFactor.tv);

    expect(find.byType(TvShell), findsOneWidget);
    expect(find.byType(LibraryShell), findsNothing);
  });

  /// A television follows no system setting: the light ramp on a screen across
  /// a dark room is a lamp, and Android TV has no light/dark switch for a user
  /// to have expressed a preference with in the first place.
  testWidgets('a television is dark whatever the system says', (tester) async {
    await launch(tester, FormFactor.tv);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      app.darkTheme!.scaffoldBackgroundColor,
      FileFinPalette.dark.background,
    );
  });

  testWidgets('a phone follows the system, and carries both ramps', (
    tester,
  ) async {
    await launch(tester, FormFactor.phone);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.scaffoldBackgroundColor, FileFinPalette.light.background);
    expect(
      app.darkTheme!.scaffoldBackgroundColor,
      FileFinPalette.dark.background,
    );
  });

  /// Every action the TV shell hands back to the route that built it. Each was
  /// a closure nothing invoked: the rail could reach them, but no assertion
  /// followed one through to what it does.
  testWidgets('the TV rail reaches the server picker', (tester) async {
    await launch(tester, FormFactor.tv);

    await dpadActivate(tester, 'Attic NAS');
    await tester.pumpAndSettle();

    expect(find.text('Servers'), findsOneWidget);
  });

  testWidgets('the TV rail reaches the playback settings sheet', (
    tester,
  ) async {
    await launch(tester, FormFactor.tv);

    await dpadActivate(tester, 'Settings');
    await tester.pumpAndSettle();

    expect(find.byType(PlaybackSettingsSheet), findsOneWidget);
  });

  /// **A television could not sign out at all**, and nothing said so: the
  /// shell took an `onSignOut` no widget invoked. The phone puts it behind the
  /// header's sliders menu, which a rail has no counterpart for, so it lives in
  /// the one sheet the Settings destination opens.
  testWidgets('sign-out is in the TV settings sheet, and it ends the session', (
    tester,
  ) async {
    await launch(tester, FormFactor.tv);

    await dpadActivate(tester, 'Settings');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signOut')));
    await tester.pumpAndSettle();

    expect(api.calls, contains('logout'));
    expect(find.byType(TvShell), findsNothing);
    // And the SHEET is gone. Deleting its `Navigator.pop` survived the last
    // sweep: sign-out still happened and the shell still went, so every
    // assertion above passed while the sheet sat over the signed-out screen
    // with nothing behind it to dismiss it.
    expect(find.byType(PlaybackSettingsSheet), findsNothing);
  });

  /// The other side of it: the phone must NOT grow a second sign-out, because
  /// two paths to a destructive action is one people reach by accident.
  testWidgets('the phone sheet carries no sign-out row', (tester) async {
    await launch(tester, FormFactor.phone);

    await chooseHeaderAction(tester, 'Playback settings');

    expect(find.byKey(const Key('signOut')), findsNothing);
  });

  /// The player route, which is the one thing the two shells build
  /// differently: the same page at the television's sizing.
  testWidgets('a television opens the player at the TV sizing', (
    tester,
  ) async {
    api
      ..playbackHeadersResult = const PlaybackSessionHeaders({'Cookie': 'x'})
      ..categoriesResult = const [
        Category(id: CategoryId(1), leaf: 'Films', name: 'Films', media: 1),
      ]
      ..categoryMediaResult = const [
        MediaSummary(id: MediaId('e4285edb34d5'), title: 'Woodstock'),
      ]
      ..mediaDetailResult = const MediaDetail(
        id: MediaId('e4285edb34d5'),
        title: 'Woodstock',
        files: [FileInfo(name: 'Woodstock.mp4', ext: '.mp4')],
      );
    await launch(tester, FormFactor.tv);

    await dpadActivate(tester, 'Library');
    await tester.pumpAndSettle();
    await dpadActivate(tester, 'Films');
    await tester.pumpAndSettle();
    await dpadActivate(tester, 'Woodstock');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<PlayerPage>(find.byType(PlayerPage)).metrics,
      PlayerControlsMetrics.tv,
    );
  });
}
