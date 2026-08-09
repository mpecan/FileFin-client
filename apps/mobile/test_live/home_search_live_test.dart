@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/home_page.dart';
import 'package:filefin_mobile/src/browse/media_row.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/browse/search_page.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fakes.dart';
import 'support/live.dart';

/// F5 and F6 against a **real `filefin` binary**, and exactly where the
/// boundary is.
///
/// **What is real here:** the server process, the seeded library on disk, the
/// socket, the cookie jar, every payload, and the widgets that render them.
///
/// **What is not:** the calls the widgets make. A request initiated inside a
/// `testWidgets` body registers its timers in that body's `FakeAsync` zone and
/// never completes — measured at M3.0 and re-learned at M3.7. So the live calls
/// happen in `setUpAll`, and the screens are then driven over *those same
/// objects*.
///
/// **The suite creates the state it asserts on, and M6.0/E-2 forces that.** A
/// `FixtureRun` copy starts with the `user_state` mirror *contradicting*
/// `meta.json` — the film's `meta.json` says watched while the copied mirror
/// says the show is — so `/api/home`, search and the category listings each
/// report the OPPOSITE of `/api/media/{id}` until something writes. One write
/// repairs one row. The alternative was to teach `fixture_run.dart` to write
/// the mirror as well, and it was rejected: that would put a second
/// transcription of `db.UpsertUserState`'s own projection into our harness,
/// where an upstream schema change would make it silently wrong rather than
/// loudly absent. A suite that writes what it reads needs no such copy and
/// says the same thing on a machine whose seed was never captured against.
/// Everything but the poster fetches, which are a property of the tiles rather
/// than of the screen's own request.
List<String> listingCalls(FakeLibraryApi api) =>
    api.calls.where((c) => !c.startsWith('posterBytes')).toList();

void main() {
  late LibraryApi api;
  late HomeRows rows;
  late MediaSummary film;
  late MediaSummary show;
  late List<MediaSummary> byTitle;
  late List<MediaSummary> byYear;
  late List<MediaSummary> refusedYear;

  setUpAll(() async {
    // `flutter_test`'s binding installs an HttpOverrides that answers 400 for
    // every request (measured at M3.0). Restoring real sockets is what makes
    // this a live suite at all.
    HttpOverrides.global = null;
    api = await liveApi();
    final categories = await api.categories();
    film = (await api.categoryMedia(
      categories.firstWhere((c) => c.leaf == 'Films').id,
    )).single;
    show = (await api.categoryMedia(
      categories.firstWhere((c) => c.leaf == 'Shows').id,
    )).single;

    // The state this suite asserts on, written through the client under test.
    await api.clearWatched(film.id);
    await api.clearWatched(show.id);
    await api.setFavorite(film.id, favorite: true);
    await api.postProgress(
      film.id,
      const ProgressReport(file: FileIndex(0), position: 45, duration: 100),
    );
    await api.setWatched(show.id, watched: true);

    rows = await api.home();
    byTitle = await api.search(film.title, field: SearchField.title);
    byYear = await api.search('${film.year}', field: SearchField.year);
    refusedYear = await api.search('nineteen', field: SearchField.year);
  });

  test('the real home rows put one item in TWO of them', () async {
    // The property the whole home screen is designed around, taken from a live
    // server rather than from a fixture: the buckets are independent predicates
    // over one `user_state` row, not a partition. The film has progress and is
    // favourited, so it is in both.
    expect(rows.continueRow.map((m) => m.id), contains(film.id));
    expect(rows.favorites.map((m) => m.id), contains(film.id));
    expect(rows.completed.map((m) => m.id), contains(show.id));
    expect(rows.completed.map((m) => m.id), isNot(contains(film.id)));
  });

  test('the real search answers the real title and the real year', () {
    expect(byTitle.map((m) => m.id), contains(film.id));
    expect(byYear.map((m) => m.id), contains(film.id));
    // The numeric scope failing closed, live: indistinguishable on the wire
    // from an empty library, which is why the client refuses it first.
    expect(refusedYear, isEmpty);
    expect(searchIsRunnable('nineteen', field: SearchField.year), isFalse);
  });

  testWidgets('the home screen renders the real rows, film in two of them', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final offline = FakeLibraryApi()
      ..homeResult = rows
      ..posterResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(api: offline, title: 'live', onOpen: (_) {}),
      ),
    );
    await tester.pump();

    expect(find.text(film.title), findsNWidgets(2));
    expect(find.text(show.title), findsOneWidget);
    expect(
      tester.widgetList<MediaRow>(find.byType(MediaRow)).map((r) => r.label),
      ['Continue watching', 'Favourites', 'Watched'],
    );
    // Poster requests are filtered out rather than asserted: the seeded film
    // has artwork, so a tile fetches it, and the claim here is about the
    // LISTING being fetched once.
    expect(listingCalls(offline), ['home']);
  });

  testWidgets('the search screen renders the real results for a real query', (
    tester,
  ) async {
    final offline = FakeLibraryApi()
      ..searchResult = byTitle
      ..posterResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          api: offline,
          onOpen: (_) {},
          debounce: Duration.zero,
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), film.title);
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.widgetWithText(PosterTile, film.title), findsOneWidget);
    // The identifiers, not just the words: the fake answers the same list
    // whatever it is handed, so the wire is the only thing that can tell a
    // dropped scope from a kept one.
    expect(listingCalls(offline), ['search(${film.title}, all)']);
  });

  testWidgets('a live year the client refuses never reaches the wire', (
    tester,
  ) async {
    // `refusedYear` came back `[]` from the real binary, and on the wire that
    // is indistinguishable from an empty library. The screen says which.
    final offline = FakeLibraryApi()
      ..searchResult = refusedYear
      ..posterResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          api: offline,
          onOpen: (_) {},
          debounce: Duration.zero,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(DropdownButton<SearchField>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nineteen');
    await tester.pump(const Duration(milliseconds: 1));

    expect(listingCalls(offline), isEmpty);
    expect(find.textContaining('is not a year'), findsOneWidget);
  });
}
