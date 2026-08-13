import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:filefin_mobile/src/browse/watch_actions.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// F8's play affordance on the detail screen.
///
/// Split out of `media_detail_page_test.dart` because that file crossed
/// `file-size`'s 400-line soft warning, and a gate warning may fall or hold
/// and never rise.
void main() {
  group('the play affordance guards', _guardCases);

  late FakeLibraryApi api;

  setUp(() {
    api = FakeLibraryApi();
  });

  group('F8 — the play affordance, and it never invents a position', () {
    MediaDetail detailWith({
      int files = 1,
      int continueIndex = 0,
      int continueSeconds = 0,
      bool watched = false,
    }) => MediaDetail(
      id: const MediaId('e4285edb34d5'),
      title: 'Direct Play Movie',
      files: [
        for (var i = 0; i < files; i++)
          FileInfo(index: FileIndex(i), name: 'File $i', size: 10),
      ],
      continueIndex: continueIndex,
      continueSeconds: continueSeconds,
      watched: watched,
    );

    Future<List<String>> pumpDetail(
      WidgetTester tester,
      MediaDetail detail,
    ) async {
      final played = <String>[];
      api.mediaDetailResult = detail;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaDetailPage(
            api: api,
            item: const MediaSummary(
              id: MediaId('e4285edb34d5'),
              title: 'Direct Play Movie',
            ),
            onPlay: (_, file, startAt) async {
              played.add('${file.value}@${startAt.inSeconds}');
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return played;
    }

    testWidgets('a fresh item offers Play and nothing else', (tester) async {
      await pumpDetail(tester, detailWith());

      expect(find.text('Play'), findsOneWidget);
      expect(find.textContaining('Continue'), findsNothing);
    });

    testWidgets('a partly watched item offers Resume AND Start over', (
      tester,
    ) async {
      final played = await pumpDetail(
        tester,
        detailWith(files: 2, continueIndex: 1, continueSeconds: 125),
      );

      // The button NAMES the file it would resume, which is stronger than the
      // clock alone: a screen that resumed file 0 at 2:05 renders an identical
      // timestamp and a different word.
      expect(find.text('Resume File 1 · 2:05'), findsOneWidget);
      await tester.tap(find.text('Resume File 1 · 2:05'));
      expect(played, ['1@125']);

      await tester.tap(find.byTooltip('Start over'));
      expect(played, ['1@125', '0@0']);
    });

    testWidgets('a watched item offers Play, never a resume', (tester) async {
      // `offerResume` is upstream's own rule: a watched item has nothing to
      // continue, however far the pointer got.
      await pumpDetail(
        tester,
        detailWith(
          files: 2,
          continueIndex: 1,
          continueSeconds: 30,
          watched: true,
        ),
      );

      expect(find.text('Play'), findsOneWidget);
      expect(find.textContaining('Continue'), findsNothing);
    });

    testWidgets('tapping a file row starts THAT file, at its own position', (
      tester,
    ) async {
      // `startSecondsFor` seeks only when the picked file IS the continue
      // file, matching the server's own client — so picking episode 1 after
      // leaving off in episode 2 starts episode 1 at the beginning.
      final played = await pumpDetail(
        tester,
        detailWith(files: 2, continueIndex: 1, continueSeconds: 125),
      );

      await tester.tap(find.text('File 0'));
      await tester.tap(find.text('File 1'));

      expect(played, ['0@0', '1@125']);
    });

    testWidgets('with no onPlay there is no affordance at all', (tester) async {
      api.mediaDetailResult = detailWith();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaDetailPage(
            api: api,
            item: const MediaSummary(
              id: MediaId('e4285edb34d5'),
              title: 'Direct Play Movie',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Play'), findsNothing);
    });
  });

  group('F9 — what the player leaves behind reaches the screen', () {
    const item = MediaSummary(
      id: MediaId('e4285edb34d5'),
      title: 'Direct Play Movie',
    );
    const detail = MediaDetail(
      id: MediaId('e4285edb34d5'),
      title: 'Direct Play Movie',
      files: [FileInfo(name: 'File 0', size: 10)],
    );

    Future<void> pumpWithOutcome(
      WidgetTester tester,
      PlaybackOutcome? outcome,
    ) async {
      api.mediaDetailResult = detail;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaDetailPage(
            api: api,
            item: item,
            onPlay: (_, _, _) async => outcome,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();
    }

    testWidgets('the prediction is applied WITHOUT a second fetch', (
      tester,
    ) async {
      // F9's second clause, and until M4.R/P3 nothing in the app read it: the
      // fold was computed, validated against 601 captured vectors and thrown
      // away, so coming back from the player showed the offset from before
      // playback started.
      await pumpWithOutcome(
        tester,
        const PlaybackOutcome(
          state: WatchState(
            pointer: ResumePointer(file: FileIndex(0), seconds: 125),
          ),
          needsDetailRefetch: false,
        ),
      );

      // No file name on the button: this item has ONE file, so naming it
      // would print the title twice — see `resumeLabel`.
      expect(find.text('Resume 2:05'), findsOneWidget);
      expect(
        api.calls.where((c) => c.startsWith('mediaDetail')),
        hasLength(1),
        reason: 'F9 says reflect it locally, without a full refetch',
      );
    });

    testWidgets('a diverged prediction is re-read instead of trusted', (
      tester,
    ) async {
      // M1's latch, discharged. `applyProgress` cannot match the server for a
      // crossing report on a single-file item — `(0, 0)` on the wire cannot
      // say whether the pointer is fresh or absent — so this is the one input
      // class that pays for a round trip rather than predicting.
      api.mediaDetailResult = detail;
      await pumpWithOutcome(
        tester,
        const PlaybackOutcome(
          state: WatchState(
            pointer: ResumePointer(file: FileIndex(0), seconds: 95),
          ),
          needsDetailRefetch: true,
        ),
      );

      expect(
        api.calls.where((c) => c.startsWith('mediaDetail')),
        hasLength(2),
      );
      // The SERVER's answer, not the prediction's 1:35.
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('a route that popped without an outcome changes nothing', (
      tester,
    ) async {
      await pumpWithOutcome(tester, null);

      expect(find.text('Play'), findsOneWidget);
      expect(
        api.calls.where((c) => c.startsWith('mediaDetail')),
        hasLength(1),
      );
    });
  });

  /// **The pointer can name a file the list no longer holds.** `continueIndex`
  /// is per item on the server and the file list is rebuilt by the importer,
  /// so an episode deleted between two sessions leaves a pointer past the end.
  /// `offerResume` still offers it — upstream's rule is about the numbers, not
  /// about the array — and the button must name SOMETHING rather than throw a
  /// `StateError` out of `build`.
  test('a resume pointing at a missing file falls back to the first', () {
    const detail = MediaDetail(
      id: MediaId('e4285edb34d5'),
      title: 'Gone',
      files: [
        FileInfo(name: 'S1E1'),
        FileInfo(index: FileIndex(1), name: 'S1E2'),
      ],
      continueIndex: 9,
      continueSeconds: 125,
    );

    expect(
      resumeLabel(
        detail,
        const ResumeAvailable(file: FileIndex(9), seconds: 125),
      ),
      'Resume S1E1 · 2:05',
    );
  });
}

/// The two guards in front of the play affordance, and the disjunction that
/// decides whether the resume button names its file.
void _guardCases() {
  MediaDetail withFiles(List<FileInfo> files) =>
      MediaDetail(id: const MediaId('a'), files: files);

  /// `files.isEmpty || play == null` weakened to `&&` survived: an item with
  /// no files would then offer a Play button that opens nothing, and a screen
  /// with no player wired would offer one that goes nowhere.
  testWidgets('an item with no files offers no play button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailActions(
            detail: withFiles(const []),
            actions: WatchActions(api: FakeLibraryApi(), publish: (_) {}),
            onPlay: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('Play'), findsNothing);
  });

  testWidgets('a screen that cannot play offers no play button either', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailActions(
            detail: withFiles(const [FileInfo(name: 'a')]),
            actions: WatchActions(api: FakeLibraryApi(), publish: (_) {}),
            onPlay: null,
          ),
        ),
      ),
    );

    expect(find.text('Play'), findsNothing);
  });

  /// `season > 0 || episode > 0 || name.isNotEmpty` — each disjunct alone has
  /// to be enough, and `just mutants` showed nothing pinned them apart.
  group('the resume button names its file when the name identifies it', () {
    const choice = ResumeAvailable(file: FileIndex(1), seconds: 65);
    MediaDetail two(FileInfo second) =>
        withFiles([const FileInfo(name: 'first'), second]);

    test('a season alone is enough', () {
      expect(
        resumeLabel(
          two(const FileInfo(index: FileIndex(1), season: 2)),
          choice,
        ),
        'Resume S2E0 · 1:05',
      );
    });

    test('an episode alone is enough', () {
      expect(
        resumeLabel(
          two(const FileInfo(index: FileIndex(1), episode: 3)),
          choice,
        ),
        'Resume S0E3 · 1:05',
      );
    });

    test('a name alone is enough', () {
      expect(
        resumeLabel(
          two(const FileInfo(index: FileIndex(1), name: 'Reel two')),
          choice,
        ),
        'Resume Reel two · 1:05',
      );
    });

    /// None of the three: `fileLabel` would fall back to `File 1`, which tells
    /// the user nothing while costing the clock its legibility.
    test('none of the three leaves the clock alone', () {
      expect(
        resumeLabel(two(const FileInfo(index: FileIndex(1))), choice),
        'Resume 1:05',
      );
    });
  });
}
