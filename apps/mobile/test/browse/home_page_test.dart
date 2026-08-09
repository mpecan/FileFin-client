import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/home_page.dart';
import 'package:filefin_mobile/src/browse/media_row.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// F6's three rows, against the payload the real server actually sent.
///
/// `home_populated.json` is captured, not written: it is the answer
/// `tool/testserver/capture_fixtures.sh` got from v0.20.3 after favouriting the
/// film and marking the show watched. It is the fixture this screen most needs
/// because of one property no hand-written literal would have thought to
/// include — **the film is in `continue` AND in `favorites`**. The buckets are
/// independent predicates over one `user_state` row, not a partition, so an
/// item appears in as many rows as match it and a screen that de-duplicated
/// would silently drop it from one.
void main() {
  final rows = HomeRows.fromJson(
    jsonDecode(
          File('../../test/fixtures/home_populated.json').readAsStringSync(),
        )
        as Map<String, Object?>,
  );

  late FakeLibraryApi api;

  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi()..posterResult = null;
  });

  final homeKey = GlobalKey<HomePageState>();

  Future<void> show(
    WidgetTester tester, {
    Object? result,
    void Function(MediaSummary)? onOpen,
    VoidCallback? onSettings,
    Size surface = const Size(800, 1600),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    api.homeResult = result ?? rows;
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          key: homeKey,
          api: api,
          title: 'Attic NAS',
          onOpen: onOpen ?? (_) {},
          onSettings: onSettings,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the captured payload really does hold the film twice', (
    tester,
  ) async {
    // The fixture's own property, asserted before anything is drawn: if a
    // re-capture ever loses it, this file's headline case becomes vacuous and
    // says so here rather than by quietly passing.
    expect(rows.continueRow.single.id, rows.favorites.single.id);
    expect(rows.completed.single.id.value, '919ac9caad25');
    await show(tester);

    expect(find.text('Direct Play Movie'), findsNWidgets(2));
    expect(find.text('Transcode Show'), findsOneWidget);
  });

  testWidgets('the three rows are labelled, in the order the server sends', (
    tester,
  ) async {
    await show(tester);

    final labels = tester
        .widgetList<MediaRow>(find.byType(MediaRow))
        .map((r) => r.label);

    expect(labels, ['Continue watching', 'Favourites', 'Watched']);
  });

  testWidgets('an empty bucket draws no heading at all', (tester) async {
    await show(
      tester,
      result: HomeRows(continueRow: rows.continueRow),
    );

    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Favourites'), findsNothing);
    expect(find.text('Watched'), findsNothing);
  });

  testWidgets('three empty buckets are an empty state, not a spinner', (
    tester,
  ) async {
    await show(tester, result: const HomeRows());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
  });

  testWidgets('the rows are fetched once, and once only', (tester) async {
    await show(tester);
    await tester.pump();
    await tester.pump();

    expect(api.calls.first, 'home');
    expect(api.calls.where((c) => c == 'home'), hasLength(1));
  });

  testWidgets('tapping a poster opens THAT item', (tester) async {
    // The identifier, not merely that something was opened: `FakeLibraryApi`
    // answers the same payload whatever it is handed, so a row pushing a
    // fabricated summary renders identically.
    final opened = <MediaSummary>[];
    await show(tester, onOpen: opened.add);

    await tester.tap(find.text('Transcode Show'));

    expect(opened.single.id.value, '919ac9caad25');
  });

  testWidgets('reload() refetches all three rows', (tester) async {
    // What the detail route's `true` result triggers. Through `load()`, so an
    // in-flight fetch is cancelled rather than allowed to land afterwards.
    await show(tester);
    expect(api.calls.where((c) => c == 'home'), hasLength(1));

    await homeKey.currentState!.reload();
    await tester.pump();

    expect(api.calls.where((c) => c == 'home'), hasLength(2));
    expect(api.tokens.first!.isCancelled, isTrue);
  });

  testWidgets('a failed load explains itself and can be retried', (
    tester,
  ) async {
    await show(tester, result: CacheUnavailable(Uri.parse('http://nas/api')));

    expect(find.text('The library is unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a SessionExpired is not a dead end here either', (tester) async {
    api.homeResult = SessionExpired(Uri.parse('http://nas/api'));
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          api: api,
          title: 'Attic NAS',
          onOpen: (_) {},
          onSignIn: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Please sign in again'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('the settings action is offered here, not only on Library', (
    tester,
  ) async {
    var opened = 0;
    await show(tester, onSettings: () => opened++);

    await tester.tap(find.byTooltip('Playback settings'));

    expect(opened, 1);
  });

  testWidgets('no settings callback means no settings button', (tester) async {
    await show(tester);

    expect(find.byTooltip('Playback settings'), findsNothing);
  });

  group('one row, virtualised', () {
    List<MediaSummary> many(int count) => [
      for (var i = 0; i < count; i++)
        MediaSummary(
          id: MediaId(i.toRadixString(16).padLeft(12, '0')),
          title: 'Item $i',
        ),
    ];

    Future<void> row(WidgetTester tester, List<MediaSummary> items) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaRow(
              api: api,
              label: 'Continue watching',
              items: items,
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('2000 items build a bounded number of tiles', (tester) async {
      // `homeBucket` applies no limit, so a heavy user's Watched row is as long
      // as their library (SPEC.md L2 — nothing on this server paginates).
      await row(tester, many(2000));

      expect(find.byType(PosterTile).evaluate().length, greaterThan(0));
      expect(find.byType(PosterTile).evaluate().length, lessThan(40));
    });

    testWidgets('it builds its children lazily, not from a list', (
      tester,
    ) async {
      await row(tester, many(2000));

      expect(
        tester.widget<ListView>(find.byType(ListView)).childrenDelegate,
        isA<SliverChildBuilderDelegate>(),
      );
    });

    testWidgets('an empty row is nothing at all — no heading, no strip', (
      tester,
    ) async {
      await row(tester, const []);

      expect(find.text('Continue watching'), findsNothing);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('a one-item row IS drawn — the other side of that boundary', (
      tester,
    ) async {
      await row(tester, many(1));

      expect(find.text('Continue watching'), findsOneWidget);
      expect(find.byType(PosterTile), findsOneWidget);
    });

    testWidgets('a poster in a row is a legal tap target', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await row(tester, many(20));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

      handle.dispose();
    });
  });
}
