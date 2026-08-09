import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/browse/category_tree_page.dart';
import 'package:filefin_mobile/src/browse/home_page.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  late Directory dir;
  late FakeLibraryApi api;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-app-');
    api = FakeLibraryApi();
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  Widget shell() => FileFinScope(
    dependencies: AppDependencies(
      network: FakeNetworkStatus(),
      playbackHostFactory: fakeHostFactory(),
      settings: SettingsStore(dir),
      apiFactory: (_) => api,
    ),
    child: const FileFinApp(),
  );

  /// Selects the Library tab.
  ///
  /// **Home is tab 0 from M6.7 and the tabs are built lazily**, so the
  /// category tree does not exist — and issues no request — until this runs.
  Future<void> openLibrary(WidgetTester tester) async {
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
  }

  testWidgets('a first launch lands on the no-server empty state', (
    tester,
  ) async {
    await tester.pumpWidget(shell());

    expect(find.text('No server yet'), findsOneWidget);
    expect(
      find.text(
        'Add the address of your FileFin server to browse its library.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the empty state is an empty state, not a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(shell());

    // A first launch has nothing to wait for. A spinner here would be a lie
    // about work that is not happening, and it is the shape this screen is
    // most likely to drift into.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the empty state offers the add-server flow', (tester) async {
    await tester.pumpWidget(shell());

    await tester.tap(find.text('Add a server'));
    await tester.pumpAndSettle();

    expect(find.text('Add a server'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('the shell is one MaterialApp with the Material 3 theme', (
    tester,
  ) async {
    // Built with a runtime key rather than `const`, which is also what makes
    // the constructor a line coverage can see: a canonicalised const
    // invocation runs nothing at all, and `MAX_UNCOVERED=0` reported exactly
    // that when every construction in the suite was const.
    final key = GlobalKey();
    late ThemeData theme;
    await tester.pumpWidget(
      FileFinScope(
        dependencies: AppDependencies(
          network: FakeNetworkStatus(),
          playbackHostFactory: fakeHostFactory(),
          settings: SettingsStore(dir),
          apiFactory: (_) => api,
        ),
        child: FileFinApp(key: key),
      ),
    );
    theme = Theme.of(tester.element(find.byType(NoServerPage)));

    expect(key.currentWidget, isA<FileFinApp>());
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.brightness, Brightness.light);
  });

  testWidgets('with nothing saved there is no sign-in affordance', (
    tester,
  ) async {
    // A "Sign in" button with no server to sign in to is a route to nowhere.
    await tester.pumpWidget(shell());

    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('add a server, sign in, and land on the library', (
    tester,
  ) async {
    // The whole M3.5 flow through the real widgets, with only the socket
    // faked. Nothing else in this suite proves the screens are actually wired
    // to each other rather than each correct on its own.
    api
      ..probeResult = const FileFinServer('0.20.3')
      ..loginResult = const AuthResult(user: 'sam')
      ..categoriesResult = const [
        Category(id: CategoryId(1), leaf: 'Films', name: 'Films'),
      ];
    await tester.pumpWidget(shell());

    await tester.tap(find.text('Add a server'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'http://192.168.1.10:8099');
    await tester.tap(find.text('Check this address'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to 192.168.1.10'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // Home is the landing tab from M6.7 and its app bar carries the server
    // name; the tree is one tap away and is not built — or fetched — before
    // that tap.
    expect(find.text('192.168.1.10'), findsOneWidget);
    await openLibrary(tester);
    expect(find.text('Films'), findsOneWidget);
  });

  testWidgets('a saved-but-signed-out server signs in without re-adding', (
    tester,
  ) async {
    // L1 makes this the common path, not an edge case: server sessions live
    // in memory and die with the process, so the launch after a server
    // restart is exactly this screen.
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
    api
      ..loginResult = const AuthResult(user: 'sam')
      ..categoriesResult = const <Category>[];
    await tester.pumpWidget(shell());

    expect(find.text('Signed out'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Attic NAS'), findsOneWidget);
    await openLibrary(tester);
    expect(find.textContaining('no categories yet'), findsOneWidget);
  });

  /// Saves one server, signs in to it, and lands on the shell.
  ///
  /// The two sign-out cases below both need a signed-in shell and neither is
  /// about how one is reached, so the flow is here rather than copied twice.
  Future<void> signIn(WidgetTester tester) async {
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
    api.loginResult = const AuthResult(user: 'sam');
    await tester.pumpWidget(shell());
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
  }

  testWidgets('signing out ends the SERVER session, not only this app', (
    tester,
  ) async {
    // The whole of M7.1. A sign-out that only dropped the client left the
    // session alive on the server and — from M7.2, where the store persists —
    // the password in the Keychain, so the next launch signed the user
    // straight back in. `logout()` is what ends both, and nothing in
    // `apps/mobile/` called it for two milestones (M7.0/E-1).
    await signIn(tester);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('logout'));
    expect(api.closed, isTrue, reason: 'the client is released after logout');
    expect(find.text('Signed out'), findsOneWidget);
  });

  testWidgets('a logout the server refuses still signs the user out here', (
    tester,
  ) async {
    // Someone who taps sign out while the server is down must still end up
    // signed out. `SessionManager.logout`'s `finally` guarantees the secrets
    // half; this is the app half, and without it a dead server is a user who
    // cannot leave.
    await signIn(tester);
    api.logoutResult = ConnectionFailed(
      Uri.parse('http://nas.local/api/logout'),
    );

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('logout'));
    expect(find.text('Signed out'), findsOneWidget);
    expect(
      find.textContaining('Cannot reach the server'),
      findsOneWidget,
      reason: 'the failure is said out loud rather than swallowed',
    );
  });

  testWidgets('signed in, the app lands on Home with Library a tap away', (
    tester,
  ) async {
    api
      ..probeResult = const FileFinServer('0.20.3')
      ..loginResult = const AuthResult(user: 'sam')
      ..categoriesResult = const [
        Category(id: CategoryId(1), leaf: 'Films', name: 'Films', media: 2),
      ];
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

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'hunter2');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    // NAMED WIDGETS, not the server name. Both tabs' app bars carry the title,
    // so `find.text('Attic NAS')` matches either one and `openLibrary`'s tap is
    // a no-op when the shell is already there: making the shell land on Library
    // instead turned seven cases in `library_shell_test.dart` red and left this
    // one green (M6.R/P2.8), while its own name is the claim about where the
    // app lands.
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(CategoryTreePage), findsNothing);

    await openLibrary(tester);

    expect(find.byType(CategoryTreePage), findsOneWidget);
    expect(find.byType(HomePage), findsNothing, reason: 'Home went offstage');
    expect(find.text('Films'), findsOneWidget);
  });
}
