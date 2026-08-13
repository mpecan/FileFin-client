import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/detail_header.dart';
import 'package:filefin_mobile/src/browse/watch_actions.dart';
import 'package:filefin_mobile/src/browse/watch_state_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Where the header's three controls actually LAND, which no other case asks.
///
/// The header is a fixed-height [Stack]: the poster and its gradient fill it,
/// the back button and the heart sit in a `SafeArea` over the top, and the
/// title block is `Positioned` against the bottom. Nothing in that arrangement
/// is checked by a `findsOneWidget` — every widget exists, correctly, on top
/// of every other one.
///
/// Which is how the back arrow came to be drawn ACROSS the title on a Pixel 10
/// Pro XL and no test noticed: `Row` centres its children on the cross axis by
/// default, and a `Row` handed the stack's full height centres a 48-point
/// button in the middle of a 186-point header — right where the title is.
void main() {
  const detail = MediaDetail(
    id: MediaId('e4285edb34d5'),
    title: 'Fawlty Towers',
    year: 1975,
    genres: ['Comedy'],
    files: [
      FileInfo(season: 1, episode: 1),
      FileInfo(index: FileIndex(1), season: 2, episode: 1),
    ],
  );

  /// Draws the header under a status bar [inset] points tall.
  ///
  /// The inset is the whole point: at zero the centred row happened to clear
  /// the title by seventeen points, so a test written without one passes
  /// against the defect. Every phone this ships to has one — 50 is a Pixel 10
  /// Pro XL's, measured off the device the overlap was found on.
  Future<void> show(WidgetTester tester, {double inset = 50}) async {
    final api = FakeLibraryApi();
    final actions = WatchActions(api: api, publish: (_) {});
    addTearDown(actions.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(top: inset)),
          child: Scaffold(
            body: DetailHeader(
              api: api,
              detail: detail,
              actions: actions,
              posterToken: CancelToken(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the back button clears the title it sits above', (tester) async {
    await show(tester);

    expect(
      tester.getRect(find.byTooltip('Back')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Fawlty Towers')).top),
    );
  });

  /// The heart is in the same row and inherits the same defect. Asserted
  /// against the title rather than against the facts line beneath it: the
  /// facts line sits low enough that a centred heart cleared it anyway, so an
  /// assertion written there passes against the bug it was meant to catch.
  testWidgets('the favourite button clears the title band', (tester) async {
    await show(tester);

    expect(
      tester.getRect(find.byType(FavouriteButton)).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Fawlty Towers')).top),
    );
  });

  /// How far the back button sits below the top of the safe area.
  ///
  /// Material's own padding around the glyph, and nothing else — so it is a
  /// small constant. **Centred, it is neither**: it was 48 points under a
  /// 50-point status bar and 33 under an 80-point one, because a centred row
  /// splits whatever height is left over. An offset that MOVES with the inset
  /// is the signature of the defect; one that holds is the signature of the
  /// fix.
  double topGap(WidgetTester tester, double inset) =>
      tester.getRect(find.byTooltip('Back')).top - inset;

  /// Pinned rather than merely "somewhere above the title": a row that drifted
  /// halfway down would still clear a short title, and the clearance
  /// assertions above would go on passing until a long one wrapped to two
  /// lines.
  testWidgets('the controls are pinned to the top of the safe area', (
    tester,
  ) async {
    await show(tester);
    expect(topGap(tester, 50), lessThan(8));
  });

  /// The status bar is not a constant and the row has to follow it, which is
  /// the half of the property a single inset cannot state.
  testWidgets('a taller status bar moves them by exactly its own height', (
    tester,
  ) async {
    await show(tester);
    final atFifty = topGap(tester, 50);

    await show(tester, inset: 80);

    expect(topGap(tester, 80), closeTo(atFifty, 0.01));
    expect(
      tester.getRect(find.byTooltip('Back')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Fawlty Towers')).top),
    );
  });
}
