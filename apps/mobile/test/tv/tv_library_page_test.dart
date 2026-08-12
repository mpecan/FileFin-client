import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_grid.dart';
import 'package:filefin_mobile/src/tv/tv_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dpad.dart';
import '../support/fakes.dart';

/// F4 on a television: the tree on the left, the chosen category's grid on the
/// right, and a remote that has to get between the two.
void main() {
  const films = Category(
    id: CategoryId(1),
    leaf: 'Films',
    name: 'Films',
    media: 12,
    files: 14,
  );
  const shows = Category(
    id: CategoryId(2),
    leaf: 'Shows',
    name: 'Shows',
    media: 3,
  );
  const woodstock = MediaSummary(
    id: MediaId('e4285edb34d5'),
    title: 'Woodstock',
  );

  late FakeLibraryApi api;

  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi()
      ..posterResult = null
      ..categoriesResult = const [films, shows]
      ..categoryMediaResult = const [woodstock];
  });

  Future<List<MediaSummary>> show(WidgetTester tester) async {
    final opened = <MediaSummary>[];
    await pumpTv(
      tester,
      Scaffold(
        body: TvLibraryPage(api: api, onOpen: opened.add),
      ),
    );
    return opened;
  }

  /// **The whole library is not requested to draw a tree.** A category's items
  /// arrive when it is chosen, which on a server with two hundred categories is
  /// the difference between one request and two hundred.
  testWidgets('nothing is fetched for the grid until a category is chosen', (
    tester,
  ) async {
    await show(tester);

    expect(api.calls, ['categories']);
    expect(find.byType(MediaGrid), findsNothing);
    expect(find.textContaining('Choose a category'), findsOneWidget);
  });

  testWidgets('choosing a category with the remote fills the grid', (
    tester,
  ) async {
    await show(tester);

    await dpadActivate(tester, 'Films');
    await tester.pumpAndSettle();

    // The identifier, not merely that something was asked for: the fake
    // answers the same payload whatever id it is handed.
    expect(api.calls, ['categories', 'categoryMedia(1)']);
    expect(find.byType(MediaGrid), findsOneWidget);
    expect(find.text('Woodstock'), findsOneWidget);
  });

  /// Choosing another category must cancel the first one's request rather than
  /// let it land on a grid that has moved on — the same rule every other
  /// screen's `AsyncController` follows.
  testWidgets('choosing a second category cancels the first request', (
    tester,
  ) async {
    await show(tester);

    await dpadActivate(tester, 'Films');
    await tester.pumpAndSettle();
    await dpadActivate(tester, 'Shows');
    await tester.pumpAndSettle();

    expect(api.calls, ['categories', 'categoryMedia(1)', 'categoryMedia(2)']);
    expect(api.tokens[1]!.isCancelled, isTrue);
  });

  /// `library.go:73-81` returns both counts as 0 when the cache is unavailable,
  /// exactly as it does for a genuinely empty category, so the heading must not
  /// state as a fact something it cannot know.
  testWidgets('a category with no counts says so in words, never "0"', (
    tester,
  ) async {
    api.categoriesResult = const [
      Category(id: CategoryId(9), leaf: 'Uncounted', name: 'Uncounted'),
    ];
    await show(tester);

    expect(find.text('No items listed'), findsWidgets);
    expect(find.text('0 items · 0 files'), findsNothing);
  });

  testWidgets('a counted category prints both numbers', (tester) async {
    await show(tester);

    expect(find.text('12 items · 14 files'), findsWidgets);
  });

  testWidgets('a library with no categories is an empty state', (
    tester,
  ) async {
    api.categoriesResult = const <Category>[];
    await show(tester);

    expect(find.textContaining('no categories yet'), findsOneWidget);
  });

  testWidgets('a category with nothing in it says so, rather than nothing', (
    tester,
  ) async {
    api.categoryMediaResult = const <MediaSummary>[];
    await show(tester);

    await dpadActivate(tester, 'Films');
    await tester.pumpAndSettle();

    expect(find.textContaining('Nothing in this category'), findsOneWidget);
  });

  /// Both panes, on one walk: a tree a remote cannot leave is a grid nobody
  /// can open, and a grid it cannot leave is a library nobody can re-browse.
  testWidgets('the tree and the grid are both reachable by D-pad', (
    tester,
  ) async {
    await show(tester);
    await dpadActivate(tester, 'Films');
    await tester.pumpAndSettle();

    final reached = await dpadReachable(tester);

    expect(reached, containsAll(['Films', 'Shows', 'Woodstock']));
  });

  testWidgets('the centre button on a poster opens THAT item', (tester) async {
    final opened = await show(tester);
    await dpadActivate(tester, 'Films');
    await tester.pumpAndSettle();

    await dpadActivate(tester, 'Woodstock');

    expect(opened.single.id, woodstock.id);
  });

  testWidgets('a failed load explains itself rather than spinning', (
    tester,
  ) async {
    api.categoriesResult = CacheUnavailable(Uri.parse('http://nas/api'));
    await show(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  /// A pointer works too: Android TV boxes ship with an air-mouse remote and
  /// Google TV's phone app sends taps, so the same rows have to answer both.
  testWidgets('a tap chooses a category, as a select press does', (
    tester,
  ) async {
    await show(tester);

    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();

    expect(api.calls, ['categories', 'categoryMedia(1)']);
  });

  testWidgets('a parent expands and collapses without being chosen', (
    tester,
  ) async {
    api.categoriesResult = const [
      films,
      Category(
        id: CategoryId(7),
        parentId: CategoryId(1),
        leaf: 'Docs',
        name: 'Films/Docs',
      ),
    ];
    await show(tester);
    expect(find.text('Docs'), findsNothing);

    await tester.tap(find.byTooltip('Expand'));
    await tester.pumpAndSettle();
    expect(find.text('Docs'), findsOneWidget);
    // Expanding is not choosing: nothing was fetched for the grid.
    expect(api.calls, ['categories']);

    await tester.tap(find.byTooltip('Collapse'));
    await tester.pumpAndSettle();
    expect(find.text('Docs'), findsNothing);
  });
}
