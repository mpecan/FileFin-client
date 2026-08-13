import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_grid.dart';
import 'package:filefin_mobile/src/browse/search_field_labels.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/tv/tv_keyboard.dart';
import 'package:filefin_mobile/src/tv/tv_search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dpad.dart';
import '../support/fakes.dart';

/// F5 on a television, where the keyboard is on screen because there is no
/// other one — Android TV's system IME covers the results while it is up.
void main() {
  const anime = MediaSummary(id: MediaId('e4285edb34d5'), title: 'Bakuman');

  late FakeLibraryApi api;

  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi()
      ..posterResult = null
      ..searchResult = const [anime];
  });

  Future<List<MediaSummary>> show(WidgetTester tester) async {
    final opened = <MediaSummary>[];
    await pumpTv(
      tester,
      Scaffold(
        body: TvSearchPage(
          api: api,
          onOpen: opened.add,
          debounce: Duration.zero,
        ),
      ),
    );
    return opened;
  }

  testWidgets('it opens on a sentence and asks the server nothing', (
    tester,
  ) async {
    await show(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Type to search'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('search')), isEmpty);
  });

  /// Every key on the board, reachable with the four arrows — a letter a
  /// remote cannot get to is a word nobody can type.
  testWidgets('every key on the board is reachable by D-pad', (tester) async {
    await show(tester);

    final reached = await dpadReachable(tester);

    for (final key in TvKeyboard.keys.split('')) {
      expect(reached, contains(key), reason: 'the $key key');
    }
    expect(reached, contains('Space'));
    expect(reached, contains('Backspace'));
  });

  testWidgets('pressing keys types, and typing searches', (tester) async {
    await show(tester);

    await dpadActivate(tester, 'A');
    await dpadActivate(tester, 'B');
    await tester.pumpAndSettle();

    expect(find.text('AB'), findsOneWidget);
    expect(api.calls, contains('search(AB, all)'));
    expect(find.byType(MediaGrid), findsOneWidget);
  });

  testWidgets('backspace removes the last character, and stops at empty', (
    tester,
  ) async {
    await show(tester);

    await dpadActivate(tester, 'A');
    await dpadActivate(tester, 'Backspace');
    await tester.pumpAndSettle();
    expect(find.textContaining('Type to search'), findsOneWidget);

    // Again on an empty box: it must not throw a `RangeError` out of a
    // callback, which is what `substring` on an empty string does.
    await dpadActivate(tester, 'Backspace');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('space is a character like any other', (tester) async {
    await show(tester);

    await dpadActivate(tester, 'A');
    await dpadActivate(tester, 'Space');
    await dpadActivate(tester, 'B');
    await tester.pumpAndSettle();

    expect(api.calls, contains('search(A B, all)'));
  });

  /// `db/search.go:70` degrades an unrecognised `field` to `all` rather than
  /// erroring, so a scope the client can send and cannot name would return
  /// plausible results under the wrong label. All eleven are offered.
  testWidgets('every scope the client can send is on a reachable pill', (
    tester,
  ) async {
    await show(tester);

    final reached = await dpadReachable(tester);

    for (final field in SearchField.values) {
      expect(
        reached,
        contains(searchFieldLabel(field)),
        reason: '${field.wire} has no way in',
      );
    }
  });

  testWidgets('the SCOPE the user picked reaches the wire', (tester) async {
    await show(tester);
    await dpadActivate(tester, 'A');
    await tester.pumpAndSettle();

    await dpadActivate(tester, 'Director');
    await tester.pumpAndSettle();

    expect(api.calls, contains('search(A, director)'));
  });

  testWidgets('the centre button on a result opens THAT item', (tester) async {
    final opened = await show(tester);
    await dpadActivate(tester, 'A');
    await tester.pumpAndSettle();

    await dpadActivate(tester, 'Bakuman');

    expect(opened.single.id, anime.id);
  });

  testWidgets('nothing matched says so, quoting the query and the scope', (
    tester,
  ) async {
    api.searchResult = const <MediaSummary>[];
    await show(tester);

    await dpadActivate(tester, 'Z');
    await tester.pumpAndSettle();

    expect(find.textContaining('No matches for “Z”'), findsOneWidget);
  });

  /// The same pill, tapped rather than selected — an air-mouse remote and the
  /// Google TV phone app both send taps.
  testWidgets('a tap on a scope pill picks it too', (tester) async {
    await show(tester);
    await dpadActivate(tester, 'A');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Title'));
    await tester.pumpAndSettle();

    expect(api.calls, contains('search(A, title)'));
  });

  /// The same defect on the scope pills: `field == chosen` inverted survived,
  /// which lights the ten scopes the user did not pick.
  testWidgets('the chosen scope is the filled pill, and only it', (
    tester,
  ) async {
    await show(tester);
    await dpadActivate(tester, 'Director');
    await tester.pumpAndSettle();

    Color? fillOf(String label) => tester
        .widgetList<Container>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(Container),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.color)
        .firstWhere((c) => true, orElse: () => null);

    expect(fillOf('Director'), FileFinPalette.dark.accentFill);
    expect(fillOf('Everything'), isNot(FileFinPalette.dark.accentFill));
  });
}
