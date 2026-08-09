import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/shell_harness.dart';

/// The one reload: which routes out of the shell invalidate the home rows.
///
/// Split from `library_shell_test.dart` at M6.R, when that file crossed
/// `file-size`'s 400-line soft warning and the ratchet says a warning may fall
/// or hold and never rise. The subject is genuinely separate: everything there
/// is about which tab is on screen, everything here is about what a route that
/// wrote does on its way back.
///
/// **All three writers reach the same pop**, and each was found missing at a
/// different time: F10's four writes (M6.7), a write still on the wire when
/// Back is tapped (M6.R/P1.3), and a playback session the server accepted a
/// progress report from (M6.R/P1.2).
void main() {
  late FakeLibraryApi api;

  setUp(() {
    resetImageCache();
    api = shellApi();
  });

  Future<void> show(WidgetTester tester, {PlaybackOutcome? outcome}) =>
      showShell(tester, api, outcome: outcome);

  Future<void> tab(WidgetTester tester, String label) =>
      selectTab(tester, label);

  testWidgets('a detail that WROTE reloads the home rows exactly once', (
    tester,
  ) async {
    // The whole reason the detail route returns a bool. Every write re-stamps
    // `updated` and every bucket is ordered by it (M6.0/E-3), so "something
    // changed" is the most the screen can honestly say and a refetch is the
    // only correct answer.
    await show(tester);
    await tester.tap(find.text('Direct Play Movie'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add to favourites'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('setFavorite(e4285edb34d5, true)'));

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c == 'home'), hasLength(2));
  });

  testWidgets('a write still in flight when Back is tapped STILL reloads', (
    tester,
  ) async {
    // The release-mode half of M6.R/P1.3, and a dispose guard alone does not
    // fix it: the pop value is read the instant the screen closes, so a write
    // that had not answered yet popped `false` and Home never reloaded even
    // though the write landed. Tap favourite on a slow link, go Back: the rows
    // must still be refetched.
    final gate = Completer<void>();
    api.writeGate = gate;
    await show(tester);
    await tester.tap(find.text('Direct Play Movie'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to favourites'));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(api.calls, contains('setFavorite(e4285edb34d5, true)'));
    expect(api.calls.where((c) => c == 'home'), hasLength(2));
    expect(
      tester.takeException(),
      isNull,
      reason:
          'and nothing notified a '
          'disposed WatchActions on the way out',
    );
  });

  group('playing something reloads the rows too', () {
    const state = WatchState(watched: true);

    Future<void> playAndLeave(WidgetTester tester) async {
      // A file to play: `PlayButtons` draws nothing for an item with none.
      api.mediaDetailResult = const MediaDetail(
        id: MediaId('e4285edb34d5'),
        title: 'Direct Play Movie',
        files: [FileInfo(name: 'File 0', size: 10)],
      );
      await tester.tap(find.text('Direct Play Movie'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    testWidgets('a session the server accepted a report from DOES reload', (
      tester,
    ) async {
      // M6.R/P1.2. `wrote` was set only by F10's four writes, so watching past
      // 90% moved the item from `continue` to `completed` on the server while
      // Home kept showing it under *Continue watching*, in its pre-playback
      // position, for the rest of the session. Every progress report re-stamps
      // `updated`, which is the ordering key of all three buckets (M6.0/E-3) —
      // the milestone's own stated reason for refetching rather than
      // predicting.
      await show(
        tester,
        outcome: const PlaybackOutcome(
          state: state,
          needsDetailRefetch: false,
          wrote: true,
        ),
      );

      await playAndLeave(tester);

      expect(api.calls.where((c) => c == 'home'), hasLength(2));
    });

    testWidgets('a session that reported NOTHING does not — the other side', (
      tester,
    ) async {
      // `wrote` is `lastSent != null`, which the reporter sets only after a
      // `204`. Opening the player and closing it before any reporting trigger
      // re-stamps nothing, so there is nothing to refetch.
      await show(
        tester,
        outcome: const PlaybackOutcome(
          state: state,
          needsDetailRefetch: false,
        ),
      );

      await playAndLeave(tester);

      expect(api.calls.where((c) => c == 'home'), hasLength(1));
    });
  });

  testWidgets('a detail that wrote NOTHING does not reload — the other side', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.text('Direct Play Movie'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c == 'home'), hasLength(1));
  });

  testWidgets('a write reloads home even when home was never on screen', (
    tester,
  ) async {
    // Opened from the Library tab, so the reload cannot be a side effect of
    // the home tab rebuilding.
    await show(tester);
    await tab(tester, 'Library');
    await tester.tap(find.text('Films'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Direct Play Movie').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add to favourites'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(api.calls.where((c) => c == 'home'), hasLength(2));
  });
}
