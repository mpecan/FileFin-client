import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/episode_list.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The list the redesign put above the description, and the season tabs that
/// only exist when the files actually carry seasons.
void main() {
  FileInfo episode(int season, int number, {int size = 244000000}) => FileInfo(
    index: FileIndex(season * 10 + number),
    name: 'S${season}E$number.mkv',
    season: season,
    episode: number,
    size: size,
    ext: '.mkv',
  );

  Future<List<FileIndex>> show(
    WidgetTester tester,
    List<FileInfo> files, {
    bool playable = true,
  }) async {
    final played = <FileIndex>[];
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: fileFinTheme(FileFinPalette.dark),
        home: Scaffold(
          body: SingleChildScrollView(
            child: EpisodeList(
              files: files,
              onPlay: playable ? played.add : null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return played;
  }

  testWidgets('an item with no files draws nothing at all', (tester) async {
    await show(tester, const []);

    expect(find.byType(Row), findsNothing);
  });

  /// `season` and `episode` are **0 for a single-file item** (SPEC.md §3.3),
  /// not absent, so a film would otherwise get a tab called "Season 0".
  testWidgets('a single-file item gets no season tab', (tester) async {
    await show(tester, const [FileInfo(name: 'Woodstock.mkv', ext: '.mkv')]);

    expect(find.textContaining('Season'), findsNothing);
    expect(find.text('Woodstock.mkv'), findsOneWidget);
  });

  /// One season is still one season: a tab strip with a single tab is a
  /// control that cannot be used, above a list it does not filter.
  testWidgets('a show with one season gets no tab either', (tester) async {
    await show(tester, [episode(1, 1), episode(1, 2)]);

    expect(find.textContaining('Season'), findsNothing);
    expect(find.text('S1E1'), findsOneWidget);
    expect(find.text('S1E2'), findsOneWidget);
  });

  testWidgets('two seasons get tabs, and the first is chosen', (tester) async {
    await show(tester, [episode(1, 1), episode(2, 1), episode(2, 2)]);

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    // Season 1 only, and its count beside the tabs.
    expect(find.text('S1E1'), findsOneWidget);
    expect(find.text('S2E1'), findsNothing);
    expect(find.text('1 ep'), findsOneWidget);
  });

  testWidgets('choosing a season shows that season, and only it', (
    tester,
  ) async {
    await show(tester, [episode(1, 1), episode(2, 1), episode(2, 2)]);

    await tester.tap(find.text('Season 2'));
    await tester.pumpAndSettle();

    expect(find.text('S2E1'), findsOneWidget);
    expect(find.text('S2E2'), findsOneWidget);
    expect(find.text('S1E1'), findsNothing);
    expect(find.text('2 eps'), findsOneWidget);
  });

  testWidgets('tapping an episode plays THAT file', (tester) async {
    // The index, not merely that something was played: every row renders
    // identically, so a list that always played file 0 looks the same.
    final played = await show(tester, [episode(1, 1), episode(1, 2)]);

    await tester.tap(find.text('S1E2'));

    expect(played, [const FileIndex(12)]);
  });

  testWidgets('a screen that cannot play has no play affordance', (
    tester,
  ) async {
    await show(tester, [episode(1, 1)], playable: false);

    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    await tester.tap(find.text('S1E1'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a watched episode is marked as one', (tester) async {
    await show(tester, [
      episode(1, 1).copyWith(watched: true),
      episode(1, 2),
    ]);

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
  });

  group('the facts line under an episode name', () {
    test('carries the size, the container and the transcode verdict', () {
      expect(
        episodeFacts(episode(1, 1).copyWith(transcode: true)),
        '244 MB · mkv · transcode',
      );
    });

    /// `transcode` is the server's own verdict (`playback.go:78`), and its
    /// absence is a claim too: this file plays as bytes.
    test('says direct play by saying nothing about transcoding', () {
      expect(episodeFacts(episode(1, 1)), '244 MB · mkv');
    });

    /// Every clause is omitted when its source is the model's default, because
    /// each default is "the server said nothing" rather than a value.
    test('an unenriched file has nothing to say', () {
      expect(episodeFacts(const FileInfo()), '');
    });
  });
}
