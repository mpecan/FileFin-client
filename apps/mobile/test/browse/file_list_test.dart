/// `FileList`, and the two labels a file row is built from.
///
/// Split out of `media_detail_page_test.dart` at M6.4, which was 402 lines
/// against `file-size`'s 400-line soft warning while F10 was about to add to
/// it. The cases are unchanged.
library;

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/file_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the helpers', () {
    test('a size is rendered in the largest unit that keeps it readable', () {
      expect(humanSize(0), '0 B');
      expect(humanSize(999), '999 B');
      expect(humanSize(1000), '1.0 kB');
      // One decimal below ten, none above: "39 kB" is as precise as anyone
      // reads, and "38.6 kB" next to "5.0 MB" is a column of noise.
      expect(humanSize(38583), '39 kB');
      expect(humanSize(5 * 1000), '5.0 kB');
      expect(humanSize(5 * 1000 * 1000), '5.0 MB');
      expect(humanSize(20 * 1000 * 1000), '20 MB');
      expect(humanSize(3 * 1000 * 1000 * 1000), '3.0 GB');
      // **Powers of 1000, and that is the assertion rather than the arithmetic
      // it happens to use** (M4.R/P7): with a 1024 divisor under a kB/MB/GB
      // label these read 1.0 kB / 4.9 MB / 19 MB / 2.8 GB, and the settings
      // dropdown offered `500 * 1000 * 1000` as "477 MB".
      expect(humanSize(500 * 1000 * 1000), '500 MB');
      // The two boundaries, exactly. `just mutants` weakened both `<` to `<=`
      // with the suite green — the difference shows only AT the value, which
      // is the off-by-one §3 cites mutation testing for.
      expect(humanSize(1000 * 1000), '1.0 MB', reason: 'exactly one unit up');
      expect(humanSize(10 * 1000), '10 kB', reason: 'exactly the 10 boundary');
      expect(humanSize(4 * 1000 * 1000 * 1000 * 1000), '4.0 TB');
    });

    test('a size beyond the largest unit stays in that unit', () {
      // Rather than silently wrapping to a unit the list does not have.
      expect(humanSize(9000 * 1024 * 1024 * 1024 * 1024), endsWith(' TB'));
    });

    test('a single-file entry is named by its file, not by SxE', () {
      expect(
        fileLabel(const FileInfo(name: 'Film.mp4', ext: '.mp4')),
        'Film.mp4',
      );
    });

    test('an episode is named by SxE even when it has a name', () {
      expect(
        fileLabel(
          const FileInfo(name: 'Show - 1x2.mkv', season: 1, episode: 2),
        ),
        'S1E2',
      );
    });

    test('a nameless single file falls back to its index', () {
      expect(fileLabel(const FileInfo(index: FileIndex(3))), 'File 3');
    });

    test('a season with no episode still counts as an episode row', () {
      // Only BOTH being zero means "single file". `season: 1, episode: 0` is a
      // season folder the importer could not number, and calling it a film
      // would be worse than calling it S1E0.
      expect(fileLabel(const FileInfo(season: 1)), 'S1E0');
    });
  });

  testWidgets('a file with no extension prints its size and nothing else', (
    tester,
  ) async {
    // The `ext` default is `''` under §8's tolerant decoding, and a trailing
    // separator with nothing after it reads as a truncated line.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FileList(
            files: [FileInfo(name: 'reel', size: 42000)],
          ),
        ),
      ),
    );

    expect(find.text('42 kB'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
  });

  /// **The guard that decides whether a row plays at all**, inverted: every
  /// file becomes untappable on a screen that CAN play, and tappable on one
  /// that cannot — where `onPlay!` then throws out of a callback. The previous
  /// commit claimed this one and did not actually test it.
  testWidgets('a row plays its own file when the screen can play', (
    tester,
  ) async {
    final played = <FileIndex>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileList(
            files: const [
              FileInfo(name: 'one'),
              FileInfo(index: FileIndex(1), name: 'two'),
            ],
            onPlay: played.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('two'));

    expect(played, [const FileIndex(1)]);
  });

  testWidgets('a screen that cannot play has inert rows, not throwing ones', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FileList(files: [FileInfo(name: 'one')]),
        ),
      ),
    );

    // The tile itself carries no handler, which is what makes the tap inert
    // rather than an `onPlay!` on a null.
    expect(
      tester.widget<ListTile>(find.byType(ListTile)).onTap,
      isNull,
    );
    await tester.tap(find.text('one'));
    expect(tester.takeException(), isNull);
  });
}
