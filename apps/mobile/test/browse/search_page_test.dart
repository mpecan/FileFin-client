import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_grid.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/browse/search_field_labels.dart';
import 'package:filefin_mobile/src/browse/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// F5 on screen: the box, the scope picker, and what reaches the wire.
void main() {
  late FakeLibraryApi api;

  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi()
      ..posterResult = null
      ..searchResult = const <MediaSummary>[];
  });

  const found = [
    MediaSummary(id: MediaId('e4285edb34d5'), title: 'Direct Play Movie'),
    MediaSummary(id: MediaId('919ac9caad25'), title: 'Transcode Show'),
  ];

  Future<void> show(
    WidgetTester tester, {
    void Function(MediaSummary)? onOpen,
    Duration debounce = Duration.zero,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(
          api: api,
          onOpen: onOpen ?? (_) {},
          debounce: debounce,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButton<SearchField>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  List<String> searches() =>
      api.calls.where((c) => c.startsWith('search')).toList();

  testWidgets('an untouched screen invites a search and asks nothing (NF1)', (
    tester,
  ) async {
    // Selecting the Search tab must cost no request, and the screen must not
    // sit on a spinner it can never leave.
    await show(tester);

    expect(find.text('Type to search anything.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('the SCOPE the user picked reaches the wire', (tester) async {
    // The single most valuable assertion on this screen. An unrecognised
    // `field` degrades to `all` upstream (`db/search.go:70`), so a page that
    // dropped the selector returns plausible results and quietly ignores what
    // was picked — nothing on screen would ever say so.
    await show(tester);

    await pick(tester, 'Director');
    await type(tester, 'Kurosawa');

    expect(searches(), contains('search(Kurosawa, director)'));
    expect(searches(), isNot(contains('search(Kurosawa, all)')));
  });

  testWidgets('the shipped debounce is 300 ms, on both sides of it', (
    tester,
  ) async {
    // The page's own default, not an injected one: this is the only case that
    // exercises the constant the app actually ships.
    await tester.pumpWidget(
      MaterialApp(
        home: SearchPage(api: api, onOpen: (_) {}),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'ada');
    await tester.pump(const Duration(milliseconds: 299));
    expect(searches(), isEmpty);

    await tester.pump(const Duration(milliseconds: 2));

    expect(searches(), ['search(ada, all)']);
  });

  testWidgets('results are drawn in the SAME grid the library uses', (
    tester,
  ) async {
    api.searchResult = found;
    await show(tester);

    await type(tester, 'o');

    expect(find.byType(MediaGrid), findsOneWidget);
    expect(find.byType(PosterTile), findsNWidgets(2));
    expect(find.text('Direct Play Movie'), findsOneWidget);
  });

  testWidgets('tapping a result opens THAT item', (tester) async {
    api.searchResult = found;
    final opened = <MediaSummary>[];
    await show(tester, onOpen: opened.add);
    await type(tester, 'o');

    await tester.tap(find.text('Transcode Show'));

    expect(opened.single.id.value, '919ac9caad25');
  });

  testWidgets('nothing matched says so, quoting the query and the scope', (
    tester,
  ) async {
    await show(tester);

    await pick(tester, 'Title');
    await type(tester, 'zzz');

    expect(find.text('No matches for “zzz” in titles.'), findsOneWidget);
    expect(searches(), ['search(zzz, title)']);
  });

  testWidgets('an unparseable year explains itself and asks nothing', (
    tester,
  ) async {
    // The distinction the whole `searchIsRunnable` exercise exists for: on the
    // wire this is indistinguishable from an empty library.
    await show(tester);

    await pick(tester, 'Year');
    await type(tester, 'nineteen');

    expect(find.textContaining('is not a year'), findsOneWidget);
    expect(find.textContaining('No matches'), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('a parseable year DOES search — the other side of it', (
    tester,
  ) async {
    await show(tester);

    await pick(tester, 'Year');
    await type(tester, '1994');

    expect(searches(), ['search(1994, year)']);
    expect(find.text('No matches for “1994” in years.'), findsOneWidget);
  });

  testWidgets('clearing the box returns to the invitation, not to a spinner', (
    tester,
  ) async {
    api.searchResult = found;
    await show(tester);
    await type(tester, 'o');
    expect(find.byType(PosterTile), findsNWidgets(2));

    await type(tester, '');

    expect(find.text('Type to search anything.'), findsOneWidget);
    expect(find.byType(PosterTile), findsNothing);
  });

  testWidgets('the caption names the query that was RUN, not the box', (
    tester,
  ) async {
    // `SearchOutcome` carries its own query, so a result arriving after the
    // box has moved on cannot be captioned with text nobody searched for.
    await show(tester, debounce: const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 301));
    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();

    expect(find.text('No matches for “zzz” in anything.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 301));
    expect(find.text('No matches for “zzzz” in anything.'), findsOneWidget);
  });

  testWidgets('a failed search is the error panel, not "no matches"', (
    tester,
  ) async {
    // The distinction §2.5 turns on: an empty answer and a failure are not the
    // same event, and only one of them is worth retrying.
    api.searchResult = CacheUnavailable(Uri.parse('http://nas/api'));
    await show(tester);

    await type(tester, 'ada');

    expect(find.text('The library is unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('No matches'), findsNothing);
  });

  testWidgets('every scope the client can send is in the picker', (
    tester,
  ) async {
    // Eleven, not SPEC §3.2's seven. A scope missing from the menu is a scope
    // nobody can reach, and the enum is the wire vocabulary.
    await show(tester);

    await tester.tap(find.byType(DropdownButton<SearchField>));
    await tester.pumpAndSettle();

    for (final field in SearchField.values) {
      expect(
        find.text(searchFieldLabel(field)),
        findsWidgets,
        reason: '${field.wire} has no way in',
      );
    }
  });

  testWidgets('the box and the picker are legal tap targets', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    handle.dispose();
  });
}
