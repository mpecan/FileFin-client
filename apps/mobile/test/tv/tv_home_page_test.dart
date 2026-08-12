import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/tv/tv_home_page.dart';
import 'package:filefin_mobile/src/tv/tv_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dpad.dart';
import '../support/fakes.dart';

/// F6 on a television: the hero, the three rows, and what a remote can reach.
void main() {
  /// The captured payload whose three buckets are mutually distinguishable —
  /// see `home_page_test.dart` for why a symmetric fixture cannot bind a
  /// heading to a bucket.
  final distinct = HomeRows.fromJson(
    jsonDecode(
          File(
            '../../test/fixtures/home_rows_distinct.json',
          ).readAsStringSync(),
        )
        as Map<String, Object?>,
  );

  late FakeLibraryApi api;
  final homeKey = GlobalKey<TvHomePageState>();

  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi()..posterResult = null;
  });

  Future<List<MediaSummary>> show(WidgetTester tester, {Object? rows}) async {
    final opened = <MediaSummary>[];
    api.homeResult = rows ?? distinct;
    await pumpTv(
      tester,
      Scaffold(
        body: TvHomePage(key: homeKey, api: api, onOpen: opened.add),
      ),
    );
    return opened;
  }

  /// The *continue* bucket arrives `ORDER BY us.updated DESC` (M6.0/E-3), so
  /// its first entry is the last thing this person watched — which is what a
  /// television is switched on to carry on with.
  testWidgets('the hero is the first thing in Continue', (tester) async {
    await show(tester);

    expect(find.text('CONTINUE WATCHING'), findsOneWidget);
    expect(
      find.text(distinct.continueRow.first.title),
      findsWidgets,
    );
  });

  /// An account with nothing half-watched still has favourites, and a hero is
  /// the screen's whole shape — so it falls back rather than disappearing, and
  /// says which bucket it came from rather than claiming a resume.
  testWidgets('with nothing to continue, the hero is a favourite and says so', (
    tester,
  ) async {
    await show(
      tester,
      rows: HomeRows(favorites: distinct.favorites),
    );

    expect(find.text('FROM YOUR FAVOURITES'), findsOneWidget);
    expect(find.text('CONTINUE WATCHING'), findsNothing);
  });

  testWidgets('three empty buckets are an empty state, not a spinner', (
    tester,
  ) async {
    await show(tester, rows: const HomeRows());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
    expect(find.byType(TvHero), findsNothing);
  });

  testWidgets('each heading draws ITS OWN bucket, not merely three rows', (
    tester,
  ) async {
    await show(tester);

    final byLabel = {
      for (final row in tester.widgetList<TvRow>(find.byType(TvRow)))
        row.label: row.items,
    };

    expect(byLabel['Continue'], distinct.continueRow);
    expect(byLabel['Favourites'], distinct.favorites);
    expect(byLabel['Watched'], distinct.completed);
  });

  testWidgets('an empty bucket draws no heading at all', (tester) async {
    await show(tester, rows: HomeRows(continueRow: distinct.continueRow));

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Favourites'), findsNothing);
    expect(find.text('Watched'), findsNothing);
  });

  /// The hero's button and every card in every row, with nothing but arrows.
  /// A row a remote cannot enter is a row that does not exist.
  testWidgets('the hero and every row are reachable by D-pad', (tester) async {
    await show(tester);

    final reached = await dpadReachable(tester);

    expect(reached, contains('Open'));
    for (final item in [
      ...distinct.continueRow,
      ...distinct.favorites,
      ...distinct.completed,
    ]) {
      expect(reached, contains(item.title), reason: item.title);
    }
  });

  testWidgets('the centre button on the hero opens that item', (tester) async {
    final opened = await show(tester);

    await dpadActivate(tester, 'Open');

    expect(opened.single.id, distinct.continueRow.first.id);
  });

  testWidgets('the centre button on a card opens THAT item', (tester) async {
    // The identifier, not merely that something was opened: the fake answers
    // the same payload whatever it is handed, so a row pushing a fabricated
    // summary renders identically.
    final opened = await show(tester);

    await dpadActivate(tester, distinct.completed.single.title);

    expect(opened.single.id, distinct.completed.single.id);
  });

  testWidgets('reload() refetches all three rows', (tester) async {
    // What the detail route's `true` result triggers, through the same
    // `GlobalKey` the phone shell uses.
    await show(tester);
    expect(api.calls.where((c) => c == 'home'), hasLength(1));

    await homeKey.currentState!.reload();
    await tester.pump();

    expect(api.calls.where((c) => c == 'home'), hasLength(2));
    expect(api.tokens.first!.isCancelled, isTrue);
  });

  testWidgets('a failed load explains itself rather than spinning', (
    tester,
  ) async {
    await show(tester, rows: CacheUnavailable(Uri.parse('http://nas/api')));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });
}
