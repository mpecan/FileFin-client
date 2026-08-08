@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/category_grid_page.dart';
import 'package:filefin_mobile/src/browse/category_tree_page.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fakes.dart';
import 'support/live.dart';

/// The app's own layers against a **real `filefin` binary**, and exactly where
/// the boundary is.
///
/// **What is real here:** the server process, the seeded library on disk, the
/// socket, the cookie jar, F3's retry, every payload, and the widgets that
/// render them.
///
/// **What is not:** the calls the widgets make. A request initiated inside a
/// `testWidgets` body registers its timers in that body's `FakeAsync` zone and
/// never completes — `runAsync` makes real time pass, it does not move a
/// pending socket into the real zone. Measured at M3.0 and re-learned the hard
/// way at M3.7, where a page was pumped and two real seconds were spent waiting
/// for tiles that could never arrive.
///
/// So the live calls happen in `setUpAll`, which runs outside `FakeAsync`, and
/// the widgets are then driven over **those same objects**. What the screens
/// render is what the real server sent; what is not proven is the widget layer
/// issuing the call itself. That gap is a `docs/verification-backlog.md` row,
/// not a claim quietly rounded up.
///
/// `@Timeout` is on the library so a hang fails the gate rather than wedging
/// it. `tool/run-integration.sh` runs this directory as an ordinary headless
/// `flutter test`, NOT under `integration_test/`, which the Flutter tool routes
/// to a connected device.
void main() {
  late LibraryApi api;
  late List<Category> categories;
  late List<CategoryNode> tree;
  late List<MediaSummary> films;
  late MediaDetail filmDetail;
  late List<int>? filmPoster;
  late List<int>? showPoster;

  setUpAll(() async {
    // `flutter_test`'s binding installs an HttpOverrides that answers 400 for
    // every request (measured at M3.0). Restoring real sockets is what makes
    // this a live suite at all — and it is a plain static assignment, so this
    // is a supported seam rather than a trick.
    HttpOverrides.global = null;
    api = await liveApi();
    categories = await api.categories();
    tree = buildCategoryTree(categories);
    final filmsCategory = categories.firstWhere((c) => c.leaf == 'Films');
    final showsCategory = categories.firstWhere((c) => c.leaf == 'Shows');
    films = await api.categoryMedia(filmsCategory.id);
    filmDetail = await api.mediaDetail(films.single.id);
    filmPoster = await api.posterBytes(films.single.id, size: PosterSize.tile);
    final shows = await api.categoryMedia(showsCategory.id);
    showPoster = await api.posterBytes(shows.single.id);
  });

  test('signing in to the real server yields the real category list', () {
    // The sign-in itself is the assertion: `liveApi()` throws if the server
    // refuses, and every value below came back through an authenticated
    // session.
    expect(categories.map((c) => c.leaf), containsAll(['Films', 'Shows']));
  });

  test('the real flat list assembles into the real tree', () {
    expect(tree.map((n) => n.category.leaf), ['Films', 'Shows']);
    expect(tree.first.children.single.category.leaf, 'Documentaries');
    expect(tree.first.children.single.depth, 1);
  });

  test('the real poster route answers both ways', () {
    // The film is seeded with a poster and the show deliberately without one,
    // so both branches have the real binary behind them: bytes, and the 404
    // that means "no artwork" and must never surface as an error.
    expect(filmPoster, isNotNull);
    expect(filmPoster, isNotEmpty);
    expect(showPoster, isNull);
  });

  testWidgets('the tree screen renders the real categories', (tester) async {
    final offline = FakeLibraryApi()..categoriesResult = categories;
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryTreePage(
          api: offline,
          title: 'live',
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Shows'), findsOneWidget);
    // The nested row shows its leaf. `name` is `Films/Documentaries`, which is
    // what a row rendering the wrong field would print.
    await tester.tap(find.byTooltip('Expand'));
    await tester.pump();
    expect(find.text('Documentaries'), findsOneWidget);
    expect(find.text('Films/Documentaries'), findsNothing);
    expect(offline.calls, ['categories']);
  });

  testWidgets('the grid renders the real item with its real title', (
    tester,
  ) async {
    final filmsCategory = categories.firstWhere((c) => c.leaf == 'Films');
    final offline = FakeLibraryApi()
      ..categoryMediaResult = films
      ..posterResult = filmPoster;
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryGridPage(
          api: offline,
          category: filmsCategory,
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Direct Play Movie'), findsOneWidget);
    expect(films.single.hasPoster, isTrue);
    // The IDENTIFIERS, not just the words. Until M3.R this fake answered the
    // same list whatever it was handed, so a grid asking for category 999 and
    // a tile fetching a neighbour's poster both rendered this screen exactly
    // as it is and the whole `just it` run stayed green.
    expect(offline.calls, [
      'categoryMedia(${filmsCategory.id.value})',
      'posterBytes(${films.single.id.value}, PosterSize.tile)',
    ]);
  });

  testWidgets('the detail screen renders the real metadata rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final offline = FakeLibraryApi()
      ..mediaDetailResult = filmDetail
      ..posterResult = filmPoster;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaDetailPage(api: offline, item: films.single),
      ),
    );
    await tester.pump();

    expect(find.text('Direct Play Movie'), findsWidgets);
    expect(find.text('2020'), findsOneWidget);
    // An unlabelled metadata key, straight off the real server, under its raw
    // name — the thing `metadataLabels` does NOT translate.
    expect(find.text('customKey'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Ada Lovelace'), findsOneWidget);
    expect(
      find.text(
        'Films/(2020) Direct Play Movie/(2020) Direct Play Movie.mp4',
      ),
      findsOneWidget,
    );
    expect(offline.calls.first, 'mediaDetail(${films.single.id.value})');
  });

  testWidgets('an item with no poster shows the placeholder, not an error', (
    tester,
  ) async {
    // NOT the 404 branch end to end — this label used to say it was, and it
    // is wrong: `posterResult = null` below is set by hand. The REAL 404 is
    // `showPoster`, fetched from the binary in `setUpAll` and asserted in "the
    // real poster route answers both ways". What this test proves is the other
    // half: given that null, the grid draws the placeholder rather than an
    // error. `docs/server-api.md` calls the 404 the normal answer for an
    // un-enriched library and says it must never look like a failure.
    //
    // The ImageCache is global and this key was filled by the test above, so
    // without this the poster is served from memory and the 404 branch is
    // never reached. The dedup is the point of PosterImageProvider; it also
    // means a test about a MISSING poster has to start from an empty cache.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    final offline = FakeLibraryApi()
      ..categoryMediaResult = films
      ..posterResult = null;
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryGridPage(
          api: offline,
          category: categories.firstWhere((c) => c.leaf == 'Films'),
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.movie_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
