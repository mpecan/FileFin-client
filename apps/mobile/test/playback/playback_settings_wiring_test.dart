import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/playback/playback_settings_sheet.dart';
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// The settings sheet as the *app* reaches it, which is the half
/// `playback_settings_sheet_test.dart` cannot prove.
///
/// That suite builds the sheet directly and asserts what it reports. This one
/// asserts the two things only the shell can: that there is a way in at all,
/// and that what the sheet reports reaches `settings.json` — which is what
/// makes `Refuse(wifiOnlyOnMetered)` and D10's refusal reachable from a running
/// path rather than only from a `SavedServer` a test built by hand.
void main() {
  late Directory dir;
  late FakeLibraryApi api;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-settings-');
    api = FakeLibraryApi()
      ..loginResult = const AuthResult(user: 'sam')
      ..categoriesResult = const [
        Category(id: CategoryId(1), leaf: 'Films', name: 'Films', media: 1),
      ]
      ..categoryMediaResult = const [
        MediaSummary(id: MediaId('e4285edb34d5'), title: 'Film'),
      ]
      ..mediaDetailResult = const MediaDetail(
        id: MediaId('e4285edb34d5'),
        title: 'Film',
        files: [FileInfo()],
      )
      ..playbackHeadersResult = const PlaybackSessionHeaders({'Cookie': 'x'});
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });

  Widget shell() => FileFinScope(
    dependencies: AppDependencies(
      secrets: InMemorySecretStore(),
      network: FakeNetworkStatus(),
      playbackHostFactory: fakeHostFactory(),
      nowPlayingFactory: fakeNowPlayingFactory(),
      settings: SettingsStore(dir),
      apiFactory: (_, {pin}) => api,
    ),
    child: const FileFinApp(),
  );

  void saveAtticNas() => SettingsStore(dir).write(
    AppSettings.empty.upsert(
      SavedServer(
        id: const ServerId('http://nas.local'),
        name: 'Attic NAS',
        baseUrl: Uri.parse('http://nas.local'),
        lastUser: 'sam',
      ),
    ),
  );

  Future<void> signIn(WidgetTester tester) async {
    saveAtticNas();
    await tester.pumpWidget(shell());
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  Map<String, Object?> savedJson() =>
      jsonDecode(File('${dir.path}/settings.json').readAsStringSync())!
          as Map<String, Object?>;

  testWidgets('the signed-in tree offers a way into playback settings', (
    tester,
  ) async {
    await signIn(tester);

    expect(find.byTooltip('Playback settings'), findsOneWidget);

    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaybackSettingsSheet), findsOneWidget);
    expect(find.text('Playback on Attic NAS'), findsOneWidget);
  });

  testWidgets('the signed-OUT shell offers no settings button', (tester) async {
    // The button is gated on `onSettings`, which only the signed-in branch
    // passes: a settings sheet with no server to edit has nothing to say.
    await tester.pumpWidget(shell());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Playback settings'), findsNothing);
  });

  testWidgets('turning Wi-Fi only on reaches settings.json', (tester) async {
    await signIn(tester);
    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('wifiOnly')));
    await tester.pumpAndSettle();

    final servers = savedJson()['servers']! as List<Object?>;
    final saved = servers.single! as Map<String, Object?>;
    expect(saved['wifiOnly'], isTrue);
    expect(saved['allowUnverifiedPlayback'], isFalse);
    // ONE entry, not two. The sheet edits a copy, so a change that dropped the
    // id would upsert a second server with its own cookie jar and its own pin.
    expect(servers, hasLength(1));
    expect(saved['id'], 'http://nas.local');
    expect(saved['lastUser'], 'sam', reason: 'the sign-in is not undone');
  });

  testWidgets('the sheet REOPENS holding what the last visit saved', (
    tester,
  ) async {
    // The case this file did not have, and its absence hid a data-loss bug for
    // a whole milestone: every case above opens the sheet exactly once.
    //
    // `LibraryShell` cached each tab's **widget instance**, so the Home tab's
    // settings button stayed bound to the `onSettings` closure built at
    // sign-in — and that closure closed over the `SavedServer` *value* of that
    // build. `_playbackSettings` read `prefs` fresh but handed the sheet a
    // server frozen in time, then wrote `upsert(changed)` derived from it. So
    // the second visit showed Wi-Fi only OFF, and the first toggle on that
    // visit wrote the stale `false` back over the saved `true`: F13's metered
    // guard and D10's refusal both silently reverted to their sign-in values.
    await signIn(tester);

    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('wifiOnly')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byKey(const Key('wifiOnly'))).value,
      isTrue,
      reason: 'the sheet is showing the server as it was at sign-in',
    );

    // And the half that loses the setting rather than merely mis-drawing it: a
    // change to an UNRELATED field must not carry the stale value with it.
    await tester.tap(find.byKey(const Key('allowUnverifiedPlayback')));
    await tester.pumpAndSettle();

    final saved =
        (savedJson()['servers']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(saved['allowUnverifiedPlayback'], isTrue);
    expect(saved['wifiOnly'], isTrue, reason: 'the earlier setting survived');
  });

  testWidgets('D10 and the shared block are written together', (tester) async {
    await signIn(tester);
    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('allowUnverifiedPlayback')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('progressIntervalSecs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 s').last);
    await tester.pumpAndSettle();

    final json = savedJson();
    final saved =
        (json['servers']! as List<Object?>).single! as Map<String, Object?>;
    final playback = json['playback']! as Map<String, Object?>;
    expect(saved['allowUnverifiedPlayback'], isTrue);
    expect(playback['progressIntervalSecs'], 10);
  });

  testWidgets('the player then shows D10 banner for that server', (
    tester,
  ) async {
    // The whole point of the toggle: what it changes has to be visible in the
    // running app, not only in the file. Turning it on and opening the player
    // is the shortest path from the setting to its consequence.
    //
    // The transport is set because the banner is keyed on it as well as on the
    // setting (M4.R/P5): `pinnedTls` is the one case where the sentence it
    // shows is true, and it is the only case D10's refusal exists for.
    api.transport = PlaybackTransport.pinnedTls;
    await signIn(tester);
    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('allowUnverifiedPlayback')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();

    // Home is tab 0 from M6.7, so the tree — and the grid under it — is one
    // tap away.
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Film').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pumpAndSettle();

    expect(find.byType(UnverifiedTlsBanner), findsOneWidget);
  });

  testWidgets('a settings file that cannot be written says so', (tester) async {
    await signIn(tester);
    await tester.tap(find.byTooltip('Playback settings'));
    await tester.pumpAndSettle();

    // A file where the directory should be: `createSync(recursive: true)`
    // refuses, which is the same FileSystemException a full disk or a revoked
    // permission produces and the only one a test can arrange reliably.
    dir.deleteSync(recursive: true);
    File(dir.path).writeAsStringSync('not a directory');
    addTearDown(() {
      File(dir.path).deleteSync();
      dir.createSync(recursive: true);
    });

    await tester.tap(find.byKey(const Key('wifiOnly')));
    await tester.pumpAndSettle();

    // A setting that silently did not stick is worse than one that refused,
    // so the OS's own words go on screen.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('could not save its settings file'), findsOne);
    expect(tester.takeException(), isNull);
  });
}
