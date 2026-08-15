import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/tv/tv_rail.dart';
import 'package:filefin_mobile/src/tv/tv_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dpad.dart';

/// The rail, and the two things a remote user needs from it: the words, and a
/// way in and out.
void main() {
  final destinations = [
    TvDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Home',
    ),
    TvDestination(
      icon: Icons.folder_copy_outlined,
      selectedIcon: Icons.folder_copy,
      label: 'Library',
    ),
    TvDestination(
      icon: Icons.search_outlined,
      selectedIcon: Icons.search,
      label: 'Search',
    ),
  ];

  /// A rail beside something focusable, because the rail's whole behaviour is
  /// a function of whether focus is inside it — and a rail alone on a screen
  /// holds focus from the first frame, so it could never be seen collapsed.
  Future<List<int>> show(WidgetTester tester, {int selected = 0}) async {
    final chosen = <int>[];
    await pumpTv(
      tester,
      Scaffold(
        body: Row(
          children: [
            TvRail(
              destinations: destinations,
              selected: selected,
              onSelect: chosen.add,
              serverName: 'Attic NAS',
              onServers: () => chosen.add(-1),
            ),
            Expanded(
              child: TvFocusable(
                onSelect: () {},
                child: const Center(child: Text('A poster')),
              ),
            ),
          ],
        ),
      ),
    );
    return chosen;
  }

  /// The rail is 76 points of glyphs while focus is elsewhere, which is what
  /// keeps it from pushing the content sideways under a user's cursor, and 208
  /// once they arrive — because 76 is enough to know where you are and not
  /// enough to read.
  testWidgets('it collapses to glyphs while focus is on the content', (
    tester,
  ) async {
    await show(tester);
    await dpadFocus(tester, 'A poster');

    expect(tester.getSize(find.byType(TvRail)).width, TvRail.collapsedWidth);
    expect(find.text('Home'), findsNothing);
    expect(find.text('Attic NAS'), findsNothing);
  });

  testWidgets('arriving with the D-pad widens it and names everything', (
    tester,
  ) async {
    await show(tester);
    await dpadFocus(tester, 'A poster');
    await dpadFocus(tester, 'Home');

    expect(tester.getSize(find.byType(TvRail)).width, TvRail.expandedWidth);
    for (final label in ['Home', 'Library', 'Search', 'Attic NAS']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  /// Every destination, reachable with nothing but arrow keys. The rail is a
  /// column, so `down` alone should walk the lot — but the walk tries all four
  /// directions anyway, because a rail that could only be entered and never
  /// left would pass a down-only sweep and strand the user.
  testWidgets('every destination is reachable by D-pad', (tester) async {
    await show(tester);

    final reached = await dpadReachable(tester);

    // The server row too: without it a television has no way to switch
    // servers, which is what the walk found.
    expect(
      reached,
      containsAll(['Home', 'Library', 'Search', 'Attic NAS', 'A poster']),
    );
  });

  testWidgets('the centre button selects the destination focus is on', (
    tester,
  ) async {
    final chosen = await show(tester);

    await dpadActivate(tester, 'Search');

    expect(chosen, [2]);
  });

  /// The rule down the left edge is the only thing saying which pane is
  /// showing, since the glyphs are all the same weight from two metres away.
  testWidgets('the accent rule marks the selected destination, once', (
    tester,
  ) async {
    await show(tester, selected: 1);

    final rules = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(TvRail),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color == FileFinPalette.dark.accent,
        ),
      ),
    );

    expect(rules, hasLength(1));
    expect(find.byIcon(Icons.folder_copy), findsOneWidget);
    expect(find.byIcon(Icons.folder_copy_outlined), findsNothing);
    // Inset from both ends of the 56-point row, so it reads as a mark against
    // that row rather than a border between two of them.
    expect(
      tester.getSize(
        find.byWidgetPredicate(
          (w) => w is Container && w.color == FileFinPalette.dark.accent,
        ),
      ),
      const Size(3, 28),
    );
  });

  testWidgets('the server row at the foot opens the picker', (tester) async {
    final chosen = await show(tester);

    await dpadActivate(tester, 'Attic NAS');

    expect(chosen, [-1]);
  });
}
