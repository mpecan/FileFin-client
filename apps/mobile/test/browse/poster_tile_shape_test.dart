import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_row.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  group('the two tile shapes', _tileShapeCases);
}

/// The wide tile's caption is a different shape from the poster tile's, and
/// `just mutants` inverted the branch that chooses between them with the suite
/// green — so every poster row would grow a mono year line and every Continue
/// card would lose one.
void _tileShapeCases() {
  Future<void> pumpRow(
    WidgetTester tester,
    MediaTileShape shape, {
    int year = 1970,
  }) async {
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaRow(
            api: FakeLibraryApi()..posterResult = null,
            label: 'Row',
            items: [
              MediaSummary(
                id: const MediaId('a'),
                title: 'Woodstock',
                year: year,
              ),
            ],
            onOpen: (_) {},
            shape: shape,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a wide card carries the year on its own line', (tester) async {
    await pumpRow(tester, MediaTileShape.wide);

    expect(find.text('Woodstock'), findsOneWidget);
    expect(find.text('1970'), findsOneWidget);
  });

  testWidgets('a poster tile does not', (tester) async {
    await pumpRow(tester, MediaTileShape.poster);

    expect(find.text('Woodstock'), findsOneWidget);
    expect(find.text('1970'), findsNothing);
  });

  /// A year of 0 is the model's default for a payload without one, not a film
  /// from the year zero — inverting that guard prints "0" under every
  /// un-enriched card.
  testWidgets('a wide card with no year prints no year', (tester) async {
    await pumpRow(tester, MediaTileShape.wide, year: 0);

    expect(find.text('0'), findsNothing);
  });
}
