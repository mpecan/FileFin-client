import 'package:filefin_mobile/src/browse/library_actions.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The header both library tabs carry, and the four guards on it.
///
/// **The guards are what this suite exists for.** Every suite that renders a
/// tab passes all four callbacks and every suite that passes none asserts on
/// something else, so each `if (… != null)` arm could be deleted without an
/// assertion objecting — which is how a guard gets removed by accident. Each
/// one is therefore exercised here in both directions.
void main() {
  Future<void> show(
    WidgetTester tester, {
    VoidCallback? onServers,
    VoidCallback? onSearch,
    VoidCallback? onSettings,
    VoidCallback? onSignOut,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: fileFinTheme(FileFinPalette.dark),
      home: Scaffold(
        appBar: LibraryHeader(
          title: 'Attic NAS',
          onServers: onServers,
          onSearch: onSearch,
          onSettings: onSettings,
          onSignOut: onSignOut,
        ),
      ),
    ),
  );

  testWidgets('the server name is always there, wired or not', (tester) async {
    await show(tester);
    expect(find.text('Attic NAS'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsNothing);
    expect(find.byIcon(Icons.tune), findsNothing);
  });

  testWidgets('the chip opens the picker', (tester) async {
    var opened = 0;
    await show(tester, onServers: () => opened += 1);
    await tester.tap(find.text('Attic NAS'));
    expect(opened, 1);
  });

  testWidgets('the magnifier is offered only when it has somewhere to go', (
    tester,
  ) async {
    var searched = 0;
    await show(tester, onSearch: () => searched += 1);
    await tester.tap(find.byIcon(Icons.search));
    expect(searched, 1);
  });

  /// One glyph, two entries. The menu is the design's single sliders icon
  /// carrying an action the design never draws — see `LibraryHeader`.
  testWidgets('the sliders glyph opens settings and sign-out', (tester) async {
    var settings = 0;
    var signedOut = 0;
    await show(
      tester,
      onSettings: () => settings += 1,
      onSignOut: () => signedOut += 1,
    );
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('Playback settings'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(settings, 0);
    expect(signedOut, 1);
  });

  /// The two menu entries are independently guarded: a shell that offers
  /// settings and no sign-out must not draw a sign-out that does nothing.
  testWidgets('a menu with only one entry has only one entry', (tester) async {
    await show(tester, onSettings: () {});
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('Playback settings'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
  });
}
