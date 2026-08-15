import 'package:filefin_mobile/src/shell/nav_bar.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bar exists because Material's own indicator is the wrong shape in the
/// wrong place, so the indicator is what this suite is mostly about.
void main() {
  final destinations = [
    ShellDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Home',
    ),
    ShellDestination(
      icon: Icons.video_library_outlined,
      selectedIcon: Icons.video_library,
      label: 'Library',
    ),
  ];

  Future<List<int>> show(
    WidgetTester tester, {
    required int selected,
    FileFinPalette palette = FileFinPalette.dark,
  }) async {
    final tapped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        // A key per ramp, because `MaterialApp` LERPS a theme change over
        // `kThemeAnimationDuration`: without it the second pump of a loop
        // reads the previous ramp's colours on its first frame and the case
        // passes or fails on animation timing rather than on the widget.
        key: ValueKey(palette),
        theme: fileFinTheme(palette),
        home: Scaffold(
          bottomNavigationBar: ShellNavBar(
            destinations: destinations,
            selected: selected,
            onSelect: tapped.add,
          ),
        ),
      ),
    );
    return tapped;
  }

  testWidgets('every destination is drawn, once', (tester) async {
    await show(tester, selected: 0);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });

  /// The rule is what tells a user which third they are in. Exactly one, at
  /// the selected index — a bar that drew it under every destination, or under
  /// none, would look plausible in a screenshot and say nothing.
  testWidgets('the accent rule is drawn once, over the selected third', (
    tester,
  ) async {
    await show(tester, selected: 1);
    final rules = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(ShellNavBar),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.color == FileFinPalette.dark.accent,
        ),
      ),
    );
    expect(rules, hasLength(1));

    final ruleCentre = tester.getCenter(
      find.byWidgetPredicate(
        (w) => w is Container && w.color == FileFinPalette.dark.accent,
      ),
    );
    expect(ruleCentre.dx, greaterThan(tester.getCenter(find.text('Home')).dx));
  });

  /// The selected glyph is the FILLED face. Asserted because the two icons are
  /// the same shape at a glance and swapping them is invisible to every other
  /// assertion in the tree.
  testWidgets('the selected destination shows its filled glyph', (
    tester,
  ) async {
    await show(tester, selected: 0);
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.home_outlined), findsNothing);
    expect(find.byIcon(Icons.video_library_outlined), findsOneWidget);
    expect(find.byIcon(Icons.video_library), findsNothing);
  });

  testWidgets('a tap reports the index that was tapped', (tester) async {
    final tapped = await show(tester, selected: 0);
    await tester.tap(find.text('Library'));
    expect(tapped, [1]);
  });

  /// The bar reads its colours from the ramp in force, so a phone in daylight
  /// gets the light one. Pinned on the ramp rather than on a literal, and on
  /// the property Material cannot supply — the bar's own ground.
  testWidgets('the bar is painted from the enclosing ramp', (tester) async {
    for (final palette in FileFinPalette.values) {
      await show(tester, selected: 0, palette: palette);
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(ShellNavBar),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(
        (container.decoration! as BoxDecoration).color,
        palette.bar,
        reason: 'the ${palette.name} ramp',
      );
    }
  });
}
