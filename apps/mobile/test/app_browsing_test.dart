import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:filefin_mobile/src/shell/form_factor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// Tree -> grid -> detail, and the way back out of a dead session.
///
/// Split out of `app_test.dart` at M3.R for file size. The division is by
/// subject rather than arbitrary: that file is about which screen a LAUNCH
/// lands on and the add-server flow; this one is about the three browsing
/// screens being wired to each other, which nothing in `test/browse/` can
/// prove because each of those suites builds one screen on its own.
void main() {
  late Directory dir;
  late FakeLibraryApi api;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-browse-');
    api = FakeLibraryApi();
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  /// Selects the Library tab.
  ///
  /// **Home is tab 0 from M6.7, and the tabs are built lazily**, so the
  /// category tree does not exist — and issues no request — until this runs.
  /// Every case below that is about the tree, the grid or the detail page
  /// starts here.
  Future<void> openLibrary(WidgetTester tester) async {
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
  }

  Widget shell() => FileFinScope(
    dependencies: AppDependencies(
      secrets: InMemorySecretStore(),
      network: FakeNetworkStatus(),
      playbackHostFactory: fakeHostFactory(),
      nowPlayingFactory: fakeNowPlayingFactory(),
      settings: SettingsStore(dir),
      apiFactory: (_, {pin}) => api,
    ),
    child: const FileFinApp(formFactor: FormFactor.phone),
  );

  testWidgets('tree to grid to detail, and back out again', (tester) async {
    // The three browsing screens wired to each other, which nothing in
    // test/browse/ can prove: each of those suites builds one screen on its
    // own.
    //
    // **What is asserted is the identifiers that travelled**, not merely that
    // a push happened. `FakeLibraryApi` answers the same payload whatever it
    // is handed, so a shell pushing the detail route with a fabricated
    // `MediaSummary` renders the same three screens and the same words —
    // measured, and it passed all 181 unit tests and all 33 integration
    // tests. The category id has to be the one the tree listed and the media
    // id the one the grid listed, or the wiring is only decorative.
    api
      ..loginResult = const AuthResult(user: 'sam')
      ..categoriesResult = const [
        Category(id: CategoryId(1), leaf: 'Films', name: 'Films', media: 1),
      ]
      ..categoryMediaResult = const [
        MediaSummary(id: MediaId('e4285edb34d5'), title: 'Direct Play Movie'),
      ]
      ..mediaDetailResult = const MediaDetail(
        id: MediaId('e4285edb34d5'),
        title: 'Direct Play Movie',
        year: 2020,
      );
    SettingsStore(dir).write(
      AppSettings.empty.upsert(
        SavedServer(
          id: const ServerId('http://nas.local'),
          name: 'Attic NAS',
          baseUrl: Uri.parse('http://nas.local'),
          lastUser: 'sam',
        ),
      ),
    );
    await tester.pumpWidget(shell());
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    await openLibrary(tester);
    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();
    expect(find.text('Direct Play Movie'), findsWidgets);
    expect(api.calls, contains('categoryMedia(1)'));

    await tester.tap(find.text('Direct Play Movie').first);
    await tester.pumpAndSettle();
    expect(find.text('2020'), findsOneWidget);
    expect(api.calls, contains('mediaDetail(e4285edb34d5)'));

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Attic NAS'), findsOneWidget);
  });

  /// Signs in to `Attic NAS` and leaves the tree on screen.
  Future<void> signIn(WidgetTester tester) async {
    await tester.pumpWidget(shell());
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

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

  testWidgets('a SessionExpired on the GRID is recoverable, not a dead end', (
    tester,
  ) async {
    // M3 shipped `CategoryGridPage.onSignIn` declared, documented, plumbed to
    // `AsyncView` — and never given a value. `ErrorPanel` gates the button on
    // `needsSignIn && onSignIn != null`, and because `needsSignIn` is true the
    // retry arm never fires either: on one of the two screens a user actually
    // lives in, a session expiry was "Please sign in again", no button, no
    // retry, recoverable only by finding the back gesture.
    api
      ..loginResult = const AuthResult(user: 'sam')
      ..categoriesResult = const [
        Category(id: CategoryId(1), leaf: 'Films', name: 'Films', media: 1),
      ]
      ..categoryMediaResult = SessionExpired(Uri.parse('http://nas.local/api'));
    saveAtticNas();
    await signIn(tester);

    await openLibrary(tester);
    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();
    expect(find.text('Please sign in again'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // `findsOneWidget` on the launch screen is what proves the `popUntil`:
    // without it the shell rebuilds signed-out UNDER the grid route, offstage,
    // and the user is left dismissing two routes by hand.
    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Films'), findsNothing);
  });

  testWidgets('a SessionExpired on the DETAIL page is recoverable too', (
    tester,
  ) async {
    api
      ..loginResult = const AuthResult(user: 'sam')
      ..categoriesResult = const [
        Category(id: CategoryId(1), leaf: 'Films', name: 'Films', media: 1),
      ]
      ..categoryMediaResult = const [
        MediaSummary(id: MediaId('e4285edb34d5'), title: 'Direct Play Movie'),
      ]
      ..mediaDetailResult = SessionExpired(Uri.parse('http://nas.local/api'));
    saveAtticNas();
    await signIn(tester);

    await openLibrary(tester);
    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direct Play Movie').first);
    await tester.pumpAndSettle();
    expect(find.text('Please sign in again'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Direct Play Movie'), findsNothing);
  });

  testWidgets('signing out offers the server signed out OF, not the first', (
    tester,
  ) async {
    // With two saved servers and no picker anywhere, `saved.first` sends
    // someone who signed out of their second server to their first one, and
    // nothing on screen says it happened.
    SettingsStore(dir).write(
      AppSettings.empty
          .upsert(
            SavedServer(
              id: const ServerId('http://first.local'),
              name: 'First',
              baseUrl: Uri.parse('http://first.local'),
            ),
          )
          .upsert(
            SavedServer(
              id: const ServerId('http://second.local'),
              name: 'Second',
              baseUrl: Uri.parse('http://second.local'),
              lastUser: 'sam',
            ),
          ),
    );
    api
      ..loginResult = const AuthResult(user: 'sam')
      // Home is where a signed-in launch lands, so it is where a dead session
      // is discovered. Both are set, because the second server's session is
      // gone for every route rather than for one of them.
      ..homeResult = SessionExpired(Uri.parse('http://second.local/api'))
      ..categoriesResult = SessionExpired(Uri.parse('http://second.local/api'));
    await tester.pumpWidget(shell());
    await tester.pump();

    // Reach the SECOND server's sign-in through the add-server flow, since the
    // launch screen's own button is the thing under test.
    api.probeResult = const FileFinServer('0.20.3');
    await tester.tap(find.text('Add a server'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'http://second.local');
    await tester.tap(find.text('Check this address'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to second.local'), findsOneWidget);
    expect(find.text('Sign in to First'), findsNothing);
  });

  testWidgets('a SessionExpired anywhere in browsing returns to sign-in', (
    tester,
  ) async {
    // F3 has already retried by then, so this is the one 401 that is not
    // routine. It is a state change rather than a route push because any of
    // the three screens can be the one that discovers it.
    api
      ..loginResult = const AuthResult(user: 'sam')
      // The Home tab is the one a signed-in launch lands on, so it is the
      // screen that discovers the expiry. "Anywhere" is the point of the case.
      ..homeResult = SessionExpired(Uri.parse('http://nas.local/api'))
      ..categoriesResult = SessionExpired(Uri.parse('http://nas.local/api'));
    SettingsStore(dir).write(
      AppSettings.empty.upsert(
        SavedServer(
          id: const ServerId('http://nas.local'),
          name: 'Attic NAS',
          baseUrl: Uri.parse('http://nas.local'),
          lastUser: 'sam',
        ),
      ),
    );
    await tester.pumpWidget(shell());
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Please sign in again'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Signed out'), findsOneWidget);
    // **And it did NOT log out, which is the whole distinction from
    // `_signOut`.** A `SessionExpired` means the server has already forgotten
    // this session; `logout()` also deletes the stored PASSWORD, which is what
    // F3 renews from and what F2's silent cold start needs — so routing this
    // callback to `_signOut` would turn every server restart into a password
    // prompt, the exact case F2 exists to remove. Swapping the two was green
    // across four cases before this line.
    expect(api.calls, isNot(contains('logout')));
  });
  testWidgets('tapping Play pushes the player, wired from the SCOPE', (
    tester,
  ) async {
    // The two ports playback needs — the connection sample and the engine
    // factory — come from the one scope the app is built on, which is what
    // lets a widget test substitute both without a plugin or libmpv.
    api
      ..categoriesResult = [
        const Category(id: CategoryId(1), name: 'Films', leaf: 'Films'),
      ]
      ..categoryMediaResult = [
        const MediaSummary(id: MediaId('e4285edb34d5'), title: 'Movie'),
      ]
      ..mediaDetailResult = const MediaDetail(
        id: MediaId('e4285edb34d5'),
        title: 'Movie',
        files: [FileInfo(name: 'File 0', size: 10)],
      )
      ..loginResult = const AuthResult(user: 'sam')
      ..playbackHeadersResult = const PlaybackSessionHeaders({'Cookie': 'x'});
    SettingsStore(dir).write(
      AppSettings.empty.upsert(
        SavedServer(
          id: const ServerId('http://nas.local'),
          name: 'Attic NAS',
          baseUrl: Uri.parse('http://nas.local'),
          lastUser: 'sam',
        ),
      ),
    );

    await signIn(tester);
    await openLibrary(tester);
    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-surface')), findsOneWidget);
  });
}
