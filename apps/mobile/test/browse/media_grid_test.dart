import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_grid.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// The grid on its own, because two screens now draw it.
///
/// It was `CategoryGridPage`'s body until M6.5. Search renders the same shape
/// over a different list, and the alternative to extracting it was a second
/// copy of the virtualisation — which is NF2's evidence duplicated, `just
/// dupes` at 15 lines and 50 tokens, and two places for the delegate to drift.
///
/// The properties asserted here are the ones NF2 rests on, and they are
/// asserted **on this widget** so that both callers inherit the proof rather
/// than each needing their own. `grid_test.dart` still measures them over 5000
/// real payloads through `CategoryGridPage`; this file pins the delegate and
/// the flags that make that possible.
void main() {
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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaGrid(api: api, items: items, onOpen: onOpen ?? (_) {}),
        ),
      ),
    );
    await tester.pump();
  }

  List<MediaSummary> many(int count) => [
    for (var i = 0; i < count; i++)
      MediaSummary(
        id: MediaId(i.toRadixString(16).padLeft(12, '0')),
        title: 'Item $i',
      ),
  ];

  testWidgets('it builds its children lazily, not from a list', (tester) async {
    // The delegate is the difference a live-widget count cannot see:
    // `GridView(children: [...])` builds all N widgets per frame and
    // `SliverChildListDelegate` still mounts only the visible range.
    await show(tester, many(500));

    expect(
      tester.widget<GridView>(find.byType(GridView)).childrenDelegate,
      isA<SliverChildBuilderDelegate>(),
    );
  });

  testWidgets('500 items build a bounded number of tiles', (tester) async {
    await show(tester, many(500));

    expect(find.byType(PosterTile).evaluate().length, greaterThan(0));
    expect(
      find.byType(PosterTile).evaluate().length,
      lessThan(80),
      reason: 'build and layout must be O(visible), not O(500)',
    );
  });

  testWidgets('a tile scrolled away is disposed, so its request cancels', (
    tester,
  ) async {
    // `addAutomaticKeepAlives: false` is what makes this true for any tile that
    // one day mixes in `AutomaticKeepAliveClientMixin`. Asserted on the widget
    // as well, because nothing under `apps/mobile/lib` mixes it in today, so
    // flipping the flag changes no behaviour a test could see.
    await show(tester, many(500));
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate = grid.childrenDelegate as SliverChildBuilderDelegate;

    expect(delegate.addAutomaticKeepAlives, isFalse);
    expect(delegate.childCount, 500);
  });

  testWidgets('the cache extent is a decision here, not a framework default', (
    tester,
  ) async {
    // Explicit so the invariant `grid_test.dart` measures is a property of this
    // widget rather than of whatever the framework defaults to today.
    await show(tester, many(20));

    expect(
      tester.widget<GridView>(find.byType(GridView)).scrollCacheExtent,
      const ScrollCacheExtent.pixels(400),
    );
  });

  testWidgets('a max EXTENT, so a tablet does not get three huge tiles', (
    tester,
  ) async {
    await show(tester, many(20));

    final delegate =
        tester.widget<GridView>(find.byType(GridView)).gridDelegate
            as SliverGridDelegateWithMaxCrossAxisExtent;

    expect(delegate.maxCrossAxisExtent, 160);
  });

  testWidgets('each tile asks for ITS OWN poster, at the tile size', (
    tester,
  ) async {
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

  testWidgets('tapping a tile opens THAT item', (tester) async {
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

  testWidgets('an empty list draws a grid with nothing in it, not a crash', (
    tester,
  ) async {
    // The callers decide what "empty" says — a category and a search have
    // different sentences — so this widget must simply render nothing.
    await show(tester, const []);

    expect(find.byType(PosterTile), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
