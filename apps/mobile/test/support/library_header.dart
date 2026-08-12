import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Picks [entry] out of the library header's sliders menu.
///
/// The redesign gives the header two glyphs where three actions live: the
/// design draws a magnifier and a sliders icon and no sign-out anywhere, so
/// playback settings and sign-out share the sliders glyph as a menu (see
/// `LibraryHeader`). Every suite that used to tap a tooltip now goes through
/// here, so the shape of that menu is described in one place rather than in
/// fifteen call sites.
Future<void> chooseHeaderAction(WidgetTester tester, String entry) async {
  await tester.tap(find.byIcon(Icons.tune));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pumpAndSettle();
}

/// The glyph the menu hangs off, for the suites that assert it is or is not
/// offered at all.
const IconData headerMenuIcon = Icons.tune;
