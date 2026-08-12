import 'package:flutter_test/flutter_test.dart';

/// Opens one of the detail page's two disclosure rows.
///
/// **The redesign put everything descriptive behind them, so a content
/// assertion has to open one first.** That is not a wrinkle in the tests so
/// much as the point of the screen: a collapsed `ExpansionTile` does not build
/// its children at all, which is why the fold now holds the title, how to
/// resume it and what to play rather than eleven metadata blocks.
Future<void> expandSection(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}
