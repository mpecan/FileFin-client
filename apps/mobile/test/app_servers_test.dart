import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/add_server_page.dart';
import 'package:filefin_mobile/src/servers/server_list_page.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:filefin_mobile/src/servers/sign_in_page.dart';
import 'package:filefin_mobile/src/shell/form_factor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// F11's switch, through the real widget tree, with **two** servers.
///
/// Two is not thoroughness, it is the minimum that can fail. `selectedServer`'s
/// own `==` survived mutation with one saved server because the fallback
/// returns the same object either way (M7.3), and every claim here has the same
/// shape: a switch that ignored its argument, a removal that deleted the wrong
/// secrets, a shell that kept the previous server's screens — none of them is
/// observable against a list of one.
void main() {
  late Directory dir;
  late InMemorySecretStore secrets;
  late Map<String, FakeLibraryApi> apis;

  final attic = SavedServer(
    id: const ServerId('http://attic.local'),
    name: 'Attic NAS',
    baseUrl: Uri.parse('http://attic.local'),
    lastUser: 'sam',
  );
  final work = SavedServer(
    id: const ServerId('https://work.example'),
    name: 'Work',
    baseUrl: Uri.parse('https://work.example'),
    lastUser: 'kim',
  );

  final populated = HomeRows.fromJson(
    jsonDecode(
          File('../../test/fixtures/home_populated.json').readAsStringSync(),
        )
        as Map<String, Object?>,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-switch-');
    secrets = InMemorySecretStore();
    apis = {};
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  FakeLibraryApi apiFor(SavedServer server) => apis.putIfAbsent(
    server.id.value,
    () => FakeLibraryApi(server: server.id)..posterResult = null,
  );

  FakeLibraryApi api(SavedServer server) => apis[server.id.value]!;

  Widget shell() => FileFinScope(
    dependencies: AppDependencies(
      secrets: secrets,
      network: FakeNetworkStatus(),
      playbackHostFactory: fakeHostFactory(),
      nowPlayingFactory: fakeNowPlayingFactory(),
      settings: SettingsStore(dir),
      // Keyed by server, which is the whole point: a factory answering one
      // fake whatever it is handed cannot tell a switch from a no-op.
      apiFactory: (server, {pin}) => apiFor(server),
    ),
    child: const FileFinApp(formFactor: FormFactor.phone),
  );

  /// Both servers saved, [selected] signed in and answering.
  void saveBoth({required SavedServer selected}) {
    SettingsStore(dir).write(
      AppSettings.empty.upsert(attic).upsert(work).withSelected(selected.id),
    );
    for (final server in [attic, work]) {
      apiFor(server).restoreResult = null;
    }
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Servers'));
    await tester.pumpAndSettle();
  }

  testWidgets('switching closes the previous client and signs into the new', (
    tester,
  ) async {
    // One method, one test. `_HomeRouteState` already swapped clients in two
    // places before this; a third path is a third chance to leak a socket, and
    // the leak is invisible until the process runs out of them.
    saveBoth(selected: attic);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(find.text('Attic NAS'), findsOneWidget);

    await openPicker(tester);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    expect(api(attic).closed, isTrue);
    expect(api(work).closed, isFalse);
    expect(api(work).calls, contains('restore'));
    expect(find.text('Work'), findsOneWidget);
    expect(SettingsStore(dir).read().selectedServerId, work.id);
  });

  testWidgets('the new server gets its own library, not the old one on show', (
    tester,
  ) async {
    // The measurement the plan asked for rather than the guess it offered. An
    // `Offstage` tab is not disposed, so a shell that survived the swap would
    // keep the first server's rows on screen under the second server's name —
    // and `LibraryShell`'s Home tab would never issue a request at all.
    saveBoth(selected: attic);
    apiFor(attic).homeResult = populated;
    apiFor(work).homeResult = const HomeRows();
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(find.text('Direct Play Movie'), findsWidgets);

    await openPicker(tester);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    expect(api(work).calls, contains('home'));
    expect(find.text('Direct Play Movie'), findsNothing);
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
  });

  testWidgets('a switch says it is working, and drops the old client first', (
    tester,
  ) async {
    // The same claim M7.3 makes for the cold start, on the path M7.4 added: an
    // empty state here would be a lie about work that IS happening, and the
    // window is long enough to see — it is a network round trip.
    saveBoth(selected: attic);
    final gate = Completer<void>();
    apiFor(work).restoreGate = gate;
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    await openPicker(tester);
    await tester.tap(find.text('Work'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('resuming')), findsOneWidget);
    // And the previous server's client is already gone rather than held open
    // for the length of the new server's restore.
    expect(api(attic).closed, isTrue);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('the selection is written BEFORE the restore', (tester) async {
    // The ordering `_switchTo`'s doc claims, asserted while the restore is
    // still in flight — the only moment the two orders differ. A user asked
    // for Work; a process that dies mid-restore must still open Work tomorrow.
    saveBoth(selected: attic);
    final gate = Completer<void>();
    apiFor(work).restoreGate = gate;
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    await openPicker(tester);
    await tester.tap(find.text('Work'));
    await tester.pump();

    expect(SettingsStore(dir).read().selectedServerId, work.id);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('the picker opens marking the server that is CURRENT', (
    tester,
  ) async {
    // `selected:` reaching the picker as `null` was a green one-token mutant:
    // `server_list_page_test.dart` pins the screen given a selection, and
    // nothing asserted the shell hands it one.
    saveBoth(selected: work);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    await openPicker(tester);

    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Attic NAS'),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
    );
  });

  testWidgets('a selection that cannot be written says so, and switches', (
    tester,
  ) async {
    // `_switchTo` was the one `SettingsStore.write` call site of five with no
    // handler, and runs `unawaited(...)` with no `runZonedGuarded` — so the
    // picker closed and nothing changed and nothing was said.
    saveBoth(selected: attic);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    await openPicker(tester);
    // The support directory becomes a FILE — a revoked permission or a full
    // disk, and it behaves the same in CI.
    dir.deleteSync(recursive: true);
    File(dir.path).writeAsStringSync('x');
    addTearDown(() {
      File(dir.path).deleteSync();
      dir.createSync(recursive: true);
    });

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('could not save its settings file'),
      findsWidgets,
    );
    // The switch itself is what the user asked for and goes ahead; only the
    // NEXT launch is what the message is about.
    expect(find.text('Work'), findsOneWidget);
    expect(api(work).calls, contains('restore'));
  });

  testWidgets('switching to a server whose session is gone offers THAT one', (
    tester,
  ) async {
    // `restoreResult` defaults to `SessionExpired`, which is what a store
    // holding nothing for that server really produces. Landing on the previous
    // server's sign-in screen is the failure this pins: the user asked for
    // Work and would be typing Attic's password.
    saveBoth(selected: attic);
    apiFor(work).restoreResult = SessionExpired(
      Uri.parse('https://work.example/api/me'),
    );
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    await openPicker(tester);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();

    expect(find.text('Signed out'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Work'), findsOneWidget);
  });

  testWidgets('removing the server in use ends the session it was showing', (
    tester,
  ) async {
    saveBoth(selected: attic);
    for (final kind in SecretKind.values) {
      // A REAL fingerprint for the pin, because the launch path now parses it:
      // `apiForServer` refuses a value that is not 64 hex bytes rather than
      // carrying a pin that would silently match nothing.
      await secrets.write(
        attic.id,
        kind,
        kind == SecretKind.certificatePin
            ? '0b:12:19:20:27:2e:35:3c:43:4a:51:58:5f:66:6d:74:'
                  '7b:82:89:90:97:9e:a5:ac:b3:ba:c1:c8:cf:d6:dd:e4'
            : 'attic',
      );
    }
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    await openPicker(tester);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Attic NAS'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(api(attic).closed, isTrue);
    for (final kind in SecretKind.values) {
      expect(await secrets.read(attic.id, kind), isNull);
    }
    // And the screen offers the server that is LEFT, rather than the one that
    // was just deleted.
    expect(find.text('Signed out'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to Work'), findsOneWidget);
  });

  testWidgets('removing a server that is not in use leaves the session alone', (
    tester,
  ) async {
    // The other arm of the same branch, and the one a "close the client
    // whenever anything is removed" would fail: the user is still browsing.
    saveBoth(selected: attic);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    await openPicker(tester);
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Work'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(api(attic).closed, isFalse);
    expect(find.text('Attic NAS'), findsOneWidget);
    expect(SettingsStore(dir).read().servers, [attic]);
  });

  testWidgets('signed out, the picker still reaches the OTHER server', (
    tester,
  ) async {
    // `onSignIn` on the launch screen goes to exactly one server — the one that
    // was selected — so without this a user signed out of their second server
    // could only ever get back to their first. It is also the only route to
    // removing a server you cannot sign in to.
    saveBoth(selected: attic);
    apiFor(attic).restoreResult = SessionExpired(
      Uri.parse('http://attic.local/api/me'),
    );
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();
    expect(find.text('Signed out'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Servers'));
    await tester.pumpAndSettle();

    expect(find.byType(ServerListPage), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('with nothing saved there is no picker to offer', (tester) async {
    // The other arm, and the one a `saved.isEmpty` written the wrong way round
    // would fail: a "Servers" button on a first launch opens an empty list and
    // is a route to nowhere.
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    expect(find.text('No server yet'), findsOneWidget);
    expect(find.text('Servers'), findsNothing);
  });

  testWidgets('adding from the picker leaves sign-in one route above home', (
    tester,
  ) async {
    // `_signInRoute` pops exactly once on success, and that is correct only
    // while sign-in sits directly on the launch screen. Pushing the add-server
    // flow ON TOP of the picker would leave the picker showing after a
    // successful sign-in, with the library underneath it.
    saveBoth(selected: attic);
    await tester.pumpWidget(shell());
    await tester.pumpAndSettle();

    await openPicker(tester);
    await tester.tap(find.text('Add a server'));
    await tester.pumpAndSettle();
    expect(find.byType(AddServerPage), findsOneWidget);
    expect(find.byType(SignInPage), findsNothing);

    // **Backing out is the only thing that can see this**, and asserting the
    // picker is "not found" while the add screen is on top cannot: an opaque
    // route takes the one below it out of the tree, so `findsNothing` passed
    // whether the picker had been popped or merely covered. `just mutants`
    // found exactly that — deleting the `pop()` survived.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(ServerListPage), findsNothing);
    expect(find.text('Attic NAS'), findsOneWidget);
  });
}
