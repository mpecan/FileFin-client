import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dpad.dart';
import '../support/fakes.dart';

/// The detail screen driven by a remote.
///
/// It is the one screen the TV shell pushes that was never written for a
/// television — `TvHomePage`, `TvLibraryPage` and `TvSearchPage` each have a
/// reachability walk and this has none, so nothing asked whether a remote can
/// get to the controls it draws. The season selector could not be reached,
/// which is the report this file starts from.
void main() {
  late FakeLibraryApi api;

  const summary = MediaSummary(id: MediaId('e4285edb34d5'), title: 'Fawlty');

  /// A whole show rather than three files. The episode list is what pushes
  /// the season selector's neighbours around, and six episodes is what a real
  /// series has — the first repro used three, fitted everything on screen, and
  /// reported the selector reachable.
  final twoSeasons = MediaDetail(
    id: const MediaId('e4285edb34d5'),
    title: 'Fawlty Towers',
    year: 1975,
    files: [
      for (var i = 0; i < 6; i += 1)
        FileInfo(
          index: FileIndex(i),
          name: 'Season 1 episode ${i + 1}',
          season: 1,
          episode: i + 1,
          ext: '.avi',
        ),
      for (var i = 0; i < 6; i += 1)
        FileInfo(
          index: FileIndex(6 + i),
          name: 'Season 2 episode ${i + 1}',
          season: 2,
          episode: i + 1,
          ext: '.avi',
        ),
    ],
  );

  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi()
      ..posterResult = null
      ..mediaDetailResult = twoSeasons;
  });

  /// 960x540 is the Google TV Streamer's logical size, and playback is wired
  /// the way `TvShell` wires it — without `onPlay` every episode row is an
  /// `InkWell` with a null `onTap`, which is not focusable, so the screen under
  /// test would not be the screen that ships.
  Future<void> show(WidgetTester tester) async {
    await pumpTv(
      tester,
      MediaDetailPage(
        api: api,
        item: summary,
        onPlay: (_, _, _) async => const PlaybackOutcome(
          state: WatchState(),
          needsDetailRefetch: false,
        ),
      ),
      surface: const Size(960, 540),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the season selector is reachable by D-pad', (tester) async {
    await show(tester);

    final reached = await dpadReachable(tester);

    expect(reached, contains('Season 1'), reason: 'reached: $reached');
  });

  /// The selector is ONE focus stop and left/right step between seasons, so
  /// reaching it is only half the claim — a strip that took focus and did
  /// nothing would satisfy the walk and still leave season 2 unwatchable.
  testWidgets('right on the selector switches to the next season', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('S1E1'), findsOneWidget);

    await dpadFocus(tester, 'Season 1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.text('S2E1'), findsOneWidget);
    expect(find.text('S1E1'), findsNothing);
  });

  /// And back again, because a selector that only moves forwards strands the
  /// first season the moment you leave it.
  testWidgets('left steps back', (tester) async {
    await show(tester);
    await dpadFocus(tester, 'Season 1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.text('S1E1'), findsOneWidget);
  });

  /// At the ends the press must ESCAPE rather than be swallowed: a control
  /// that eats `left` for ever is how a remote gets stuck on one row.
  testWidgets('left from the first season leaves the selector', (tester) async {
    await show(tester);
    await dpadFocus(tester, 'Season 1');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(focusedLabel(tester), isNot('Season 1'));
  });

  /// The same at the other end, and this is the half that CRASHES rather than
  /// merely sticking: without the upper guard the step indexes one past the
  /// last season and throws `RangeError` out of a key handler. `just mutants`
  /// is what asked for it — the guard was written, and no case pressed right
  /// from the last season to find out whether it held.
  testWidgets('right from the last season leaves the selector, not a crash', (
    tester,
  ) async {
    await show(tester);
    await dpadFocus(tester, 'Season 1');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('S2E1'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Still on the last season: the press left the strip rather than wrapping.
    expect(find.text('S2E1'), findsOneWidget);
  });

  /// The seasons are only the reported symptom. A screen whose controls were
  /// never walked has no reason to have exactly one gap, and each of these is
  /// a control a remote user can see and cannot use.
  testWidgets('every control on the detail screen is reachable by D-pad', (
    tester,
  ) async {
    await show(tester);

    final reached = await dpadReachable(tester);

    expect(
      reached,
      containsAll([
        'Season 1',
        'S1E1',
        'Description & cast',
        'Files & technical',
      ]),
      reason: 'reached: $reached',
    );
  });

  /// **The three header controls are reachable and have no names**, and that
  /// is recorded here rather than quietly left out of the walk above.
  ///
  /// `IconButton` builds its `Tooltip` OUTSIDE the focus node it creates, so
  /// the name is on an ancestor of the focused subtree rather than in it —
  /// the same defect the player's scrubber had before its tooltip moved inside
  /// `DpadFocusable`. A screen reader is in the position the walk is: back,
  /// favourite and watched announce as an icon code point and nothing else.
  ///
  /// Asserted as a count so it fails in BOTH directions: naming them drops it
  /// to zero and this test fails, which is the prompt to delete it.
  testWidgets('the header controls are reachable but still unnamed', (
    tester,
  ) async {
    await show(tester);

    final reached = await dpadReachable(tester);

    expect(
      reached.where((label) => label.startsWith('icon:')),
      hasLength(3),
      reason: 'reached: $reached',
    );
  });
}
