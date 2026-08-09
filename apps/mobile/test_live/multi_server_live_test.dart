@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/home_page.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fakes.dart';
import 'support/live.dart';

/// **F11 with two real servers signed into at once, from the app's layer.**
///
/// The switching UI is proven headlessly in `app_servers_test.dart`, against
/// two fakes. This is the half a fake cannot reach: two `filefin` processes,
/// two accounts, one `SecretStore`, and the question of whether the namespace
/// is the only thing keeping them apart. A suite with one server answers "the
/// client used the right credentials" and "the client used the only
/// credentials" identically.
///
/// The two accounts come from `fixture_run.dart`, which writes a second user
/// into every copy's `$HOME/.filefin.json` — one JSON edit, no new dependency
/// (M7.0/E-3; the plan expected the account to live in the SQLite cache, and it
/// does not).
void main() {
  late LibraryApi alpha;
  late LibraryApi beta;
  late AuthResult alphaUser;
  late AuthResult betaUser;
  late HomeRows alphaRows;
  late HomeRows betaRows;
  late MediaSummary film;

  setUpAll(() async {
    HttpOverrides.global = null;
    final secrets = InMemorySecretStore();
    final alphaBinary = await liveServer();
    final betaBinary = await liveServer();
    alpha = liveApiFor(alphaBinary, secrets, id: const ServerId('alpha'));
    beta = liveApiFor(betaBinary, secrets, id: const ServerId('beta'));

    await alpha.login(seededCredentials);
    await beta.login(secondCredentials);
    alphaUser = await alpha.me();
    betaUser = await beta.me();

    final categories = await alpha.categories();
    film = (await alpha.categoryMedia(
      categories.firstWhere((c) => c.leaf == 'Films').id,
    )).single;
    // Written through ONE server, so the rows below are genuinely different
    // libraries rather than two reads of the same state. Neither copy's home
    // rows depend on what any earlier fixture capture left behind.
    await alpha.setFavorite(film.id, favorite: true);
    alphaRows = await alpha.home();
    betaRows = await beta.home();
  });

  test('two servers, two accounts, one secret store', () {
    // Re-asked after both sign-ins, which is the only order in which a shared
    // cookie jar shows itself.
    expect(alphaUser.user, seededCredentials.username);
    expect(betaUser.user, secondCredentials.username);
  });

  test('a write on one server is absent from the other', () {
    expect(alphaRows.favorites.map((m) => m.id), contains(film.id));
    expect(betaRows.favorites, isEmpty);
    expect(betaRows.continueRow, isEmpty);
    expect(betaRows.completed, isEmpty);
  });

  testWidgets('the home screen shows the rows of the server it was handed', (
    tester,
  ) async {
    final offline = FakeLibraryApi()
      ..homeResult = alphaRows
      ..posterResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(api: offline, title: 'Alpha', onOpen: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text(film.title), findsWidgets);
  });

  testWidgets('the other server renders its own empty library, not the first', (
    tester,
  ) async {
    // The failure this pins is the one a shell that survived a server switch
    // produces: the second server's name over the first server's rows.
    final offline = FakeLibraryApi()
      ..homeResult = betaRows
      ..posterResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(api: offline, title: 'Beta', onOpen: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.text('Beta'), findsOneWidget);
    expect(find.text(film.title), findsNothing);
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
  });
}
