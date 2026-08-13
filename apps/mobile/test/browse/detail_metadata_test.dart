import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/detail_header.dart';
import 'package:filefin_mobile/src/browse/detail_sections.dart';
import 'package:filefin_mobile/src/browse/media_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/detail_sections.dart';
import '../support/fakes.dart';

/// What the detail screen SAYS, as opposed to what it draws: the mono facts
/// line, the count on the files row, and which of the two disclosure rows
/// exists at all. Split from `media_detail_page_test.dart` for
/// `just file-size`'s 400-line warning, which those groups pushed it over.
void main() {
  group('the header facts line', _headerFactsCases);
  group('the files summary', _filesSummaryCases);
  group('the files and technical row', _filesRowCases);
}

/// The mono facts line, and the arms `just mutants` showed nothing covered.
///
/// Each clause is omitted when its source is the model's default, and each
/// pluralises. Both halves were mutable with the suite green: dropping the
/// `> 1` arms leaves an enriched show saying nothing about its seasons, and
/// dropping the `== 1` arms says "1 seasons".
void _headerFactsCases() {
  MediaDetail withFiles(
    List<FileInfo> files, {
    int year = 0,
    List<String> genres = const [],
  }) => MediaDetail(
    id: const MediaId('a'),
    files: files,
    year: year,
    genres: genres,
  );

  test('one season and one file are singular', () {
    expect(
      headerFacts(withFiles(const [FileInfo(season: 1, episode: 1)])),
      '1 season · 1 file',
    );
  });

  test('two of each are plural', () {
    expect(
      headerFacts(
        withFiles(const [
          FileInfo(season: 1, episode: 1),
          FileInfo(index: FileIndex(1), season: 2, episode: 1),
        ]),
      ),
      '2 seasons · 2 files',
    );
  });

  /// A film has no seasons at all, so the clause is absent rather than "0".
  test('a film says nothing about seasons', () {
    expect(
      headerFacts(withFiles(const [FileInfo()], year: 1970)),
      '1970 · 1 file',
    );
  });

  test('an unenriched item has nothing to say', () {
    expect(headerFacts(withFiles(const [])), '');
  });

  test('the first genre is appended, lower-cased', () {
    expect(
      headerFacts(withFiles(const [FileInfo()], genres: ['Comedy', 'Drama'])),
      '1 file · comedy',
    );
  });
}

/// The count on the *Files & technical* row.
void _filesSummaryCases() {
  test('it names the container when there is one', () {
    expect(
      filesSummary(
        const MediaDetail(
          id: MediaId('a'),
          files: [FileInfo(ext: '.avi')],
        ),
      ),
      '1 · avi',
    );
  });

  /// `just mutants` inverted `extension != null` with the suite green, which
  /// appends `null` to the row for every file the server sent no extension
  /// for.
  test('a file with no extension leaves the count alone', () {
    expect(
      filesSummary(const MediaDetail(id: MediaId('a'), files: [FileInfo()])),
      '1',
    );
  });
}

/// The *Files & technical* row appears when EITHER half has something, and
/// `just mutants` weakened that `||` to `&&` with the suite green — which
/// hides every technical block belonging to an item whose file list the
/// server did not send.
void _filesRowCases() {
  testWidgets('technical data with no file list still gets a row', (
    tester,
  ) async {
    final api = FakeLibraryApi()
      ..mediaDetailResult = const MediaDetail(
        id: MediaId('aaaaaaaaaaaa'),
        title: 'Bare',
        technical: [MetaPair(key: 'Resolution', value: '320x240')],
      );
    await tester.binding.setSurfaceSize(const Size(800, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaDetailPage(
          api: api,
          item: const MediaSummary(id: MediaId('aaaaaaaaaaaa')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Files & technical'), findsOneWidget);
    await expandSection(tester, 'Files & technical');
    expect(find.text('320x240'), findsOneWidget);
  });
}
