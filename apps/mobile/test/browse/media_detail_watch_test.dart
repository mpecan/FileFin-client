/// F10 on the detail screen, and the asymmetry it exists to make visible.
///
/// The centrepiece is the pair at the top of `the two un-watches` — a UI that
/// collapsed `POST {"watched": false}` and `DELETE .../watched` into one
/// operation fails one of them whichever way it collapsed.
library;

import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:filefin_mobile/src/browse/watch_state_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _id = MediaId('e4285edb34d5');
const _item = MediaSummary(id: _id, title: 'Transcode Show');

/// Watched, two files, and 45 seconds into the first one.
const _watchedAt45 = MediaDetail(
  id: _id,
  title: 'Transcode Show',
  files: [
    FileInfo(),
    FileInfo(index: FileIndex(1)),
  ],
  watched: true,
  continueSeconds: 45,
);

void main() {
  late FakeLibraryApi api;

  setUp(() => api = FakeLibraryApi());

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaDetailPage(
          api: api,
          item: _item,
          onPlay: (_, _, _) async => null,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> chooseUnwatch(WidgetTester tester, String entry) async {
    await tester.tap(find.byType(PopupMenuButton<UnwatchChoice>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(entry));
    await tester.pumpAndSettle();
  }

  group('the two un-watches are two operations, on screen as on the wire', () {
    testWidgets('Mark as unwatched keeps the position: Continue 0:45 is back', (
      tester,
    ) async {
      api.mediaDetailResult = _watchedAt45;
      await pump(tester);
      // Watched, so F8 offers nothing to resume from before the tap.
      expect(find.text('Play'), findsOneWidget);
      expect(find.textContaining('Continue'), findsNothing);

      await chooseUnwatch(tester, 'Mark as unwatched');

      // The exact call list, not a `contains`: `setWatched(id, false)` and
      // `clearWatched(id)` are one character apart in intent and a whole
      // resume position apart in effect.
      expect(api.calls, [
        'mediaDetail(e4285edb34d5)',
        'setWatched(e4285edb34d5, false)',
      ]);
      expect(find.text('Continue 0:45'), findsOneWidget);
      expect(find.text('Mark watched'), findsOneWidget);
    });

    testWidgets('Clear watch state forgets it: no Continue anywhere', (
      tester,
    ) async {
      api.mediaDetailResult = _watchedAt45;
      await pump(tester);

      await chooseUnwatch(tester, 'Clear watch state');

      expect(api.calls, [
        'mediaDetail(e4285edb34d5)',
        'clearWatched(e4285edb34d5)',
      ]);
      // The discriminator. A screen that sent `setWatched(id, false)` for this
      // entry would show `Continue 0:45` here, and a screen that sent
      // `clearWatched` for the other entry would show `Play` there.
      expect(find.textContaining('Continue'), findsNothing);
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Mark watched'), findsOneWidget);
    });

    testWidgets('each entry says what it costs, in the menu', (tester) async {
      api.mediaDetailResult = _watchedAt45;
      await pump(tester);

      await tester.tap(find.byType(PopupMenuButton<UnwatchChoice>));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Keeps where you left off'),
        findsOneWidget,
      );
      expect(find.textContaining('Forgets the position too'), findsOneWidget);
    });

    testWidgets('an unwatched item offers one button, not a menu', (
      tester,
    ) async {
      api.mediaDetailResult = _watchedAt45.copyWith(watched: false);
      await pump(tester);

      expect(find.byType(PopupMenuButton<UnwatchChoice>), findsNothing);
      await tester.tap(find.text('Mark watched'));
      await tester.pump();

      expect(api.calls, [
        'mediaDetail(e4285edb34d5)',
        'setWatched(e4285edb34d5, true)',
      ]);
    });
  });

  group('favourite', () {
    testWidgets('the heart writes and fills immediately', (tester) async {
      api.mediaDetailResult = _watchedAt45;
      await pump(tester);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();

      expect(api.calls.last, 'setFavorite(e4285edb34d5, true)');
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('a favourite item un-favourites', (tester) async {
      api.mediaDetailResult = _watchedAt45.copyWith(favorite: true);
      await pump(tester);

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pump();

      expect(api.calls.last, 'setFavorite(e4285edb34d5, false)');
    });
  });

  group('rating — whole numbers, and an explicit way back to none', () {
    testWidgets('picking a number writes it', (tester) async {
      api.mediaDetailResult = _watchedAt45;
      await pump(tester);

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7').last);
      await tester.pumpAndSettle();

      expect(api.calls.last, 'setRating(e4285edb34d5, 7)');
    });

    testWidgets('Not rated is an entry, because 0 is how the server clears', (
      tester,
    ) async {
      api.mediaDetailResult = _watchedAt45.copyWith(rating: 8);
      await pump(tester);

      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not rated').last);
      await tester.pumpAndSettle();

      expect(api.calls.last, 'setRating(e4285edb34d5, 0)');
    });

    for (final rating in [0, 1, 10]) {
      testWidgets('a rating of $rating selects an item and says nothing', (
        tester,
      ) async {
        api.mediaDetailResult = _watchedAt45.copyWith(rating: rating);
        await pump(tester);

        expect(find.textContaining('outside 1-10'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final rating in [-1, 11, 99]) {
      testWidgets('a rating of $rating is shown as itself and explained', (
        tester,
      ) async {
        // Reachable: the server validates on write and NOT on read — a
        // hand-edited `meta.json` really does serve `rating: 99` (M6.0/E-6).
        // And a `DropdownButton` whose value is not among its items asserts
        // rather than rendering, so this branch is correctness, not polish.
        api.mediaDetailResult = _watchedAt45.copyWith(rating: rating);
        await pump(tester);

        expect(tester.takeException(), isNull);
        expect(find.textContaining('outside 1-10'), findsOneWidget);
        expect(find.text('$rating'), findsWidgets);
      });
    }
  });

  group('honesty about failure and about being busy', () {
    testWidgets('a refused write reverts the control and says why', (
      tester,
    ) async {
      api
        ..mediaDetailResult = _watchedAt45
        ..writeFailure = CacheUnavailable(Uri.parse('http://h/api/x'));
      await pump(tester);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();

      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.textContaining('library cache is unavailable'), findsWidgets);
    });

    testWidgets('a second write during one is refused, visibly (G5)', (
      tester,
    ) async {
      api
        ..mediaDetailResult = _watchedAt45
        ..writeGate = Completer<void>();
      await pump(tester);

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // The controls stay tappable on purpose: a greyed-out control has no way
      // to say why it is greyed out, and F10 allows exactly one write at a
      // time. The second tap is refused with a sentence instead.
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pump();

      expect(find.textContaining('Still saving'), findsOneWidget);
      expect(api.calls, [
        'mediaDetail(e4285edb34d5)',
        'setFavorite(e4285edb34d5, true)',
      ]);

      api.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  testWidgets('the screen meets the tap-target and contrast guidelines', (
    tester,
  ) async {
    api.mediaDetailResult = _watchedAt45;
    final handle = tester.ensureSemantics();
    await pump(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
