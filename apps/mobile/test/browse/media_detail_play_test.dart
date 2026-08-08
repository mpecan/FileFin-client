import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// F8's play affordance on the detail screen.
///
/// Split out of `media_detail_page_test.dart` because that file crossed
/// `file-size`'s 400-line soft warning, and a gate warning may fall or hold
/// and never rise.
void main() {
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
            onPlay: (_, file, startAt) =>
                played.add('${file.value}@${startAt.inSeconds}'),
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

    testWidgets('a partly watched item offers Continue AND Start over', (
      tester,
    ) async {
      final played = await pumpDetail(
        tester,
        detailWith(files: 2, continueIndex: 1, continueSeconds: 125),
      );

      expect(find.text('Continue 2:05'), findsOneWidget);
      await tester.tap(find.text('Continue 2:05'));
      expect(played, ['1@125']);

      await tester.tap(find.text('Start over'));
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
}
