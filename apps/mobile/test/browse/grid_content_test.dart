import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/category_grid_page.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// What the grid DRAWS, as opposed to what it costs.
///
/// Split out of `grid_test.dart` at M3.R, which is a file-size decision with a
/// reason: that file's `setUpAll` stands up a real `HttpServer` and decodes
/// 5000 payloads through the real `FileFinClient`, and none of the cases here
/// needs any of it. They are about one or two items and what appears on screen,
/// so they run against literals and a fake and cost nothing.
void main() {
  const category = Category(id: CategoryId(1), leaf: 'Films', name: 'Films');
  late FakeLibraryApi api;

  setUp(() {
    // The `ImageCache` is global and survives between tests, and
    // `PosterImageProvider` keys on (ServerId, MediaId, PosterSize) — so a
    // poster fetched by an earlier test is served from memory and no request
    // is made at all. A test that counts requests has to start empty.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi()..posterResult = null;
  });

  Future<void> show(
    WidgetTester tester,
    List<MediaSummary> items, {
    void Function(MediaSummary)? onOpen,
    Category which = category,
  }) async {
    api.categoryMediaResult = items;
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryGridPage(
          api: api,
          category: which,
          onOpen: onOpen ?? (_) {},
        ),
      ),
    );
    await tester.pump();
  }

  int posterCalls() =>
      api.calls.where((c) => c.startsWith('posterBytes')).length;

  testWidgets('each tile asks for ITS OWN poster, at the tile size', (
    tester,
  ) async {
    // Both halves are invisible to a fake that ignores its arguments, and both
    // ship: a tile rendering its neighbour's artwork looks like a library with
    // the wrong posters, and a tile that dropped `size` pulls the detail-sized
    // image for every item in a large grid. `?size=` is a hint the server may
    // ignore (`media.go:351`), so nothing on screen would say so either.
    await show(tester, const [
      MediaSummary(
        id: MediaId('aaaaaaaaaaaa'),
        title: 'First',
        hasPoster: true,
      ),
      MediaSummary(
        id: MediaId('bbbbbbbbbbbb'),
        title: 'Second',
        hasPoster: true,
      ),
    ]);

    expect(api.calls.where((c) => c.startsWith('posterBytes')), [
      'posterBytes(aaaaaaaaaaaa, PosterSize.tile)',
      'posterBytes(bbbbbbbbbbbb, PosterSize.tile)',
    ]);
  });

  testWidgets('an item with NO id gets a tile like any other', (tester) async {
    // `client.dart:196-199` is explicit that filtering bad items out of a list
    // IS the silent failure G5 forbids. The list renders as decoded and
    // opening the bad one fails loudly, naming the value.
    await show(tester, const [
      MediaSummary(title: 'No id', year: 2020),
      MediaSummary(id: MediaId('aaaaaaaaaaaa'), title: 'Fine'),
    ]);

    expect(find.byType(PosterTile), findsNWidgets(2));
    expect(find.text('No id'), findsOneWidget);
  });

  testWidgets('an item with no title still shows something', (tester) async {
    await show(tester, const [MediaSummary(id: MediaId('a'))]);

    expect(find.text('Untitled'), findsWidgets);
  });

  testWidgets('an item the server says has no poster never requests one', (
    tester,
  ) async {
    await show(tester, const [
      MediaSummary(id: MediaId('aaaaaaaaaaaa'), title: 'Bare'),
    ]);

    expect(posterCalls(), 0);
    expect(find.text('Bare'), findsWidgets);
  });

  testWidgets('tapping a tile opens that item', (tester) async {
    final opened = <MediaSummary>[];
    await show(
      tester,
      const [
        MediaSummary(id: MediaId('aaaaaaaaaaaa'), title: 'Item 0'),
        MediaSummary(id: MediaId('bbbbbbbbbbbb'), title: 'Item 3'),
      ],
      onOpen: opened.add,
    );

    await tester.tap(find.text('Item 3'));

    expect(opened.single.id.value, 'bbbbbbbbbbbb');
  });

  testWidgets('an empty category is an empty state, not a spinner', (
    tester,
  ) async {
    await show(tester, const []);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Nothing in this category'), findsOneWidget);
  });

  testWidgets('a failed listing explains itself and can be retried', (
    tester,
  ) async {
    api.categoryMediaResult = CacheUnavailable(Uri.parse('http://nas/api'));
    await tester.pumpWidget(
      MaterialApp(
        home: CategoryGridPage(
          api: api,
          category: category,
          onOpen: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('The library is unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('the app bar shows the leaf, not the full path', (tester) async {
    await show(
      tester,
      const [],
      which: const Category(
        id: CategoryId(3),
        leaf: 'Documentaries',
        name: 'Films/Documentaries',
      ),
    );

    expect(find.text('Documentaries'), findsOneWidget);
    expect(find.text('Films/Documentaries'), findsNothing);
  });
}
