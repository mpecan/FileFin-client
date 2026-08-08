import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// The committed payloads, decoded by the real model (§8). A hand-written
/// literal here would prove only that we can spell our own field names.
MediaDetail _fixture(String name) => MediaDetail.fromJson(
  jsonDecode(File('../../test/fixtures/$name.json').readAsStringSync())
      as Map<String, Object?>,
);

void main() {
  late FakeLibraryApi api;

  const summary = MediaSummary(id: MediaId('e4285edb34d5'), title: 'Tapped');

  setUp(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi();
  });

  // A tall surface, because `ListView` builds only what fits. At the default
  // 800x600 the metadata, ratings, technical and file blocks are never
  // constructed at all, so a content assertion about them fails for a reason
  // that has nothing to do with the content. Scrolling to each one instead
  // would test the scroll rather than the screen.
  Future<void> pump(
    WidgetTester tester, {
    MediaSummary? item,
    Size surface = const Size(800, 4000),
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaDetailPage(api: api, item: item ?? summary),
      ),
    );
    await tester.pump();
  }

  group('the captured direct-play payload', () {
    setUp(() => api.mediaDetailResult = _fixture('media_detail_directplay'));

    testWidgets('title, year, description and plot all render', (tester) async {
      await pump(tester);

      expect(find.text('Direct Play Movie'), findsWidgets);
      expect(find.text('2020'), findsOneWidget);
      expect(find.textContaining('A short H.264 clip'), findsOneWidget);
      expect(find.textContaining('Colour bars'), findsOneWidget);
    });

    testWidgets('an unlabelled metadata key renders under its RAW name', (
      tester,
    ) async {
      // `MetaPair.key` is a display label, not an identifier: the server
      // renders through metadataLabels/ratingLabels (media.go:80,93) and
      // anything not in the table falls through sorted under its raw name. The
      // fixture carries `customKey` precisely to keep that honest, and a
      // client that switched on the key would drop every field the server's
      // table does not know.
      await pump(tester);

      expect(find.text('customKey'), findsOneWidget);
      expect(
        find.textContaining('unlabelled keys fall through'),
        findsOneWidget,
      );
    });

    testWidgets('ratings and technical render as their own blocks', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Ratings'), findsOneWidget);
      expect(find.text('IMDb'), findsOneWidget);
      expect(find.text('Technical'), findsOneWidget);
      expect(find.text('320x240'), findsOneWidget);
    });

    testWidgets('cast, genres and tags render as chips', (tester) async {
      await pump(tester);

      expect(find.widgetWithText(Chip, 'Ada Lovelace'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Test'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'direct-play'), findsOneWidget);
    });

    testWidgets('a single-file item shows its name, never S0E0', (
      tester,
    ) async {
      // season/episode are 0 for a single-file item (SPEC.md §3.3), not
      // absent — a row that always printed them would put a season number on
      // every film in the library.
      await pump(tester);

      expect(find.textContaining('S0E0'), findsNothing);
      expect(find.text('(2020) Direct Play Movie.mp4 (.mp4)'), findsOneWidget);
    });

    testWidgets('the file path is shown verbatim, as the server sent it', (
      tester,
    ) async {
      // Relative to the server's data directory (M2's finding C3). Joining it
      // with anything produces a path that addresses nothing and looks like it
      // should.
      await pump(tester);

      expect(
        find.text(
          'Films/(2020) Direct Play Movie/(2020) Direct Play Movie.mp4',
        ),
        findsOneWidget,
      );
    });

    testWidgets('there is no playback affordance yet (M4 owns it)', (
      tester,
    ) async {
      // A button that did nothing would be a promise this milestone cannot
      // keep.
      await pump(tester);

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.text('Play'), findsNothing);
    });
  });

  group('the captured multi-file payload', () {
    setUp(
      () => api.mediaDetailResult = _fixture('media_detail_multifile_advanced'),
    );

    testWidgets('episodes show SxE, because both are non-zero', (tester) async {
      await pump(tester);

      expect(find.textContaining('S1E1'), findsOneWidget);
      expect(find.textContaining('S1E2'), findsOneWidget);
    });

    testWidgets('both files are listed with human-readable sizes', (
      tester,
    ) async {
      await pump(tester);

      expect(find.textContaining('38 kB'), findsOneWidget);
      expect(find.textContaining('37 kB'), findsOneWidget);
    });
  });

  group('an item with nothing in it', () {
    testWidgets('renders without any empty section headers', (tester) async {
      // An un-enriched library has no genres, no cast and no ratings. A header
      // over nothing reads as something missing rather than something absent.
      api.mediaDetailResult = const MediaDetail(
        id: MediaId('aaaaaaaaaaaa'),
        title: 'Bare',
      );

      await pump(tester);

      expect(find.text('Bare'), findsWidgets);
      for (final header in [
        'Genres',
        'Tags',
        'Cast',
        'Details',
        'Ratings',
        'Technical',
        'Files',
      ]) {
        expect(find.text(header), findsNothing, reason: header);
      }
    });

    testWidgets('a description with no plot renders no empty paragraph', (
      tester,
    ) async {
      // Both conditions are needed. `just mutants` weakened the `&&` to `||`
      // and the suite stayed green, which renders an empty paragraph under
      // every item whose importer filled only one of the two fields.
      api.mediaDetailResult = const MediaDetail(
        id: MediaId('aaaaaaaaaaaa'),
        title: 'Bare',
        description: 'Only a description.',
      );

      await pump(tester, item: const MediaSummary(id: MediaId('aaaaaaaaaaaa')));

      expect(find.text('Only a description.'), findsOneWidget);
      expect(find.text(''), findsNothing);
    });

    testWidgets('a plot identical to the description is shown once', (
      tester,
    ) async {
      // Some importers fill both with the same text, and printing it twice
      // looks like a bug in the app rather than in the metadata.
      api.mediaDetailResult = const MediaDetail(
        id: MediaId('aaaaaaaaaaaa'),
        title: 'Bare',
        description: 'The same words.',
        plot: 'The same words.',
      );

      await pump(tester, item: const MediaSummary(id: MediaId('aaaaaaaaaaaa')));

      expect(find.text('The same words.'), findsOneWidget);
    });

    testWidgets('a year of 0 is not printed as a year', (tester) async {
      api.mediaDetailResult = const MediaDetail(
        id: MediaId('aaaaaaaaaaaa'),
        title: 'Bare',
      );

      await pump(tester);

      expect(find.text('0'), findsNothing);
    });

    testWidgets('an item with no title is Untitled, not blank', (tester) async {
      api.mediaDetailResult = const MediaDetail(id: MediaId('aaaaaaaaaaaa'));

      await pump(tester, item: const MediaSummary(id: MediaId('aaaaaaaaaaaa')));

      expect(find.text('Untitled'), findsWidgets);
    });
  });

  testWidgets('a poster the server promised but cannot serve leaves no gap', (
    tester,
  ) async {
    // `hasPoster` is the server's claim and a claim can be wrong — the file
    // can be deleted between the listing and the fetch. A broken-image glyph
    // at the top of the detail page would report a fault about artwork nobody
    // asked after; the space simply closes up.
    api
      ..mediaDetailResult = const MediaDetail(
        id: MediaId('aaaaaaaaaaaa'),
        title: 'Promised',
        hasPoster: true,
      )
      ..posterResult = null;

    await pump(tester, item: const MediaSummary(id: MediaId('aaaaaaaaaaaa')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Promised'), findsWidgets);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an item with no id explains itself rather than crashing', (
    tester,
  ) async {
    // `MediaSummary.id` defaults to `MediaId('')` under §8's tolerant
    // decoding, and the grid renders that item like any other because
    // filtering it out IS the silent failure G5 forbids. Opening it has to
    // fail loudly and name the value.
    api.mediaDetailResult = const MalformedIdentifier('', 'media id');

    await pump(tester, item: const MediaSummary(title: 'No id'));

    expect(find.text('The server sent an item we cannot open'), findsOneWidget);
    expect(find.textContaining('media id'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('the detail load carries a token, and dispose cancels it', (
    tester,
  ) async {
    api.mediaDetailResult = _fixture('media_detail_directplay');
    await pump(tester);
    final token = api.tokens.first!;

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(token.isCancelled, isTrue);
  });

  group('the helpers', () {
    test('a size is rendered in the largest unit that keeps it readable', () {
      expect(humanSize(0), '0 B');
      expect(humanSize(1023), '1023 B');
      expect(humanSize(1024), '1.0 kB');
      // One decimal below ten, none above: "38 kB" is as precise as anyone
      // reads, and "37.7 kB" next to "5.0 MB" is a column of noise.
      expect(humanSize(38583), '38 kB');
      expect(humanSize(5 * 1024), '5.0 kB');
      expect(humanSize(5 * 1024 * 1024), '5.0 MB');
      expect(humanSize(20 * 1024 * 1024), '20 MB');
      expect(humanSize(3 * 1024 * 1024 * 1024), '3.0 GB');
      // The two boundaries, exactly. `just mutants` weakened both `<` to `<=`
      // with the suite green — the difference shows only AT the value, which
      // is the off-by-one §3 cites mutation testing for.
      expect(humanSize(1024 * 1024), '1.0 MB', reason: 'exactly one unit up');
      expect(humanSize(10 * 1024), '10 kB', reason: 'exactly the 10 boundary');
      expect(humanSize(4 * 1024 * 1024 * 1024 * 1024), '4.0 TB');
    });

    test('a size beyond the largest unit stays in that unit', () {
      // Rather than silently wrapping to a unit the list does not have.
      expect(humanSize(9000 * 1024 * 1024 * 1024 * 1024), endsWith(' TB'));
    });

    test('a single-file entry is named by its file, not by SxE', () {
      expect(
        fileLabel(const FileInfo(name: 'Film.mp4', ext: '.mp4')),
        'Film.mp4 (.mp4)',
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
}
