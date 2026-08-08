import 'package:filefin_mobile/main.dart' as entrypoint;
import 'package:filefin_mobile/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a first launch lands on the no-server empty state', (
    tester,
  ) async {
    await tester.pumpWidget(const FileFinApp());

    expect(find.text('No server yet'), findsOneWidget);
    expect(
      find.text(
        'Add the address of your FileFin server to browse its library.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the empty state is an empty state, not a spinner', (
    tester,
  ) async {
    await tester.pumpWidget(const FileFinApp());

    // A first launch has nothing to wait for. A spinner here would be a lie
    // about work that is not happening, and it is the shape this screen is
    // most likely to drift into.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('main() runs the shell', (tester) async {
    entrypoint.main();
    await tester.pump();

    expect(find.byType(FileFinApp), findsOneWidget);
    expect(find.text('No server yet'), findsOneWidget);
  });
}
