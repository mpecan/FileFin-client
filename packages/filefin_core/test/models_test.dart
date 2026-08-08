import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/model_contract.dart';

void main() {
  modelContract<ServerState>(
    'ServerState',
    payload: loadFixture('state'),
    decode: ServerState.fromJson,
    encode: (m) => m.toJson(),
    onFixture: (m) {
      expect(m.needsSetup, isFalse);
      expect(m.version, '0.20.3');
    },
    onDefaults: (m) {
      expect(m.needsSetup, isFalse);
      expect(m.version, '');
    },
  );

  modelContract<AuthResult>(
    'AuthResult',
    payload: loadFixture('login'),
    decode: AuthResult.fromJson,
    encode: (m) => m.toJson(),
    onFixture: (m) {
      expect(m.user, 'testuser');
      expect(m.admin, isTrue);
      expect(m.alias, '');
      expect(m.mdlUsername, '');
      expect(m.malUsername, '');
    },
    onDefaults: (m) {
      expect(m.user, '');
      expect(m.admin, isFalse);
    },
  );

  modelContract<Category>(
    'Category',
    payload: loadFixtureList('categories').first,
    decode: Category.fromJson,
    encode: (m) => m.toJson(),
    onFixture: (m) {
      expect(m.id, const CategoryId(1));
      expect(m.name, 'Films');
      expect(m.leaf, 'Films');
      expect(m.alias, 'Films');
      expect(m.parentId, const CategoryId(0));
      expect(m.otherMedia, isFalse);
      expect(m.position, 0);
      expect(m.empty, isFalse);
      expect(m.media, 1);
      expect(m.files, 1);
      expect(m.kind, 'both');
      expect(m.learned, 0);
    },
    onDefaults: (m) {
      expect(m.id, const CategoryId(0));
      expect(m.parentId, const CategoryId(0));
      expect(m.name, '');
      expect(m.kind, '');
      expect(m.media, 0);
    },
  );

  modelContract<MediaSummary>(
    'MediaSummary',
    payload: loadFixtureList('category_media').first,
    decode: MediaSummary.fromJson,
    encode: (m) => m.toJson(),
    onFixture: (m) {
      expect(m.id, const MediaId('e4285edb34d5'));
      expect(m.title, 'Direct Play Movie');
      expect(m.year, 2020);
      expect(m.hasPoster, isFalse);
      expect(m.watched, isFalse);
    },
    onDefaults: (m) {
      expect(m.id, const MediaId(''));
      expect(m.year, 0);
      expect(m.hasPoster, isFalse);
    },
  );

  modelContract<HomeRows>(
    'HomeRows',
    payload: loadFixture('home_populated'),
    decode: HomeRows.fromJson,
    encode: (m) => m.toJson(),
    onFixture: (m) {
      expect(m.continueRow.single.id, const MediaId('e4285edb34d5'));
      expect(m.favorites.single.id, const MediaId('e4285edb34d5'));
      expect(m.completed.single.title, 'Transcode Show');
      expect(m.completed.single.watched, isTrue);
    },
    onDefaults: (m) {
      expect(m.continueRow, isEmpty);
      expect(m.favorites, isEmpty);
      expect(m.completed, isEmpty);
    },
  );

  test("HomeRows reads the wire key 'continue', a Dart reserved word", () {
    expect(
      HomeRows.fromJson(loadFixture('home_populated')).toJson(),
      contains('continue'),
    );
    expect(
      HomeRows.fromJson(const {
        'continue': [
          {'id': 'abc'},
        ],
      }).continueRow.single.id,
      const MediaId('abc'),
    );
  });

  modelContract<MediaDetail>(
    'MediaDetail',
    payload: loadFixture('media_detail_directplay'),
    decode: MediaDetail.fromJson,
    encode: (m) => m.toJson(),
    onFixture: (m) {
      expect(m.id, const MediaId('e4285edb34d5'));
      expect(m.title, 'Direct Play Movie');
      expect(m.year, 2020);
      expect(m.description, startsWith('A short H.264 clip'));
      expect(m.plot, startsWith('Colour bars'));
      expect(m.hasPoster, isFalse);
      expect(m.files, hasLength(1));
      expect(m.metadata.last.key, 'customKey');
      expect(m.ratings.map((p) => p.key), contains('IMDb'));
      expect(m.technical.first.value, '320x240');
      expect(m.actors, contains('Grace Hopper'));
      expect(m.genres, ['Test', 'Short']);
      expect(m.tags, ['fixture', 'direct-play']);
      expect(m.watched, isFalse);
      expect(m.favorite, isFalse);
      expect(m.rating, 0);
      expect(m.continueIndex, 0);
      expect(m.continueSeconds, 0);
    },
    onDefaults: (m) {
      expect(m.id, const MediaId(''));
      expect(m.files, isEmpty);
      expect(m.metadata, isEmpty);
      expect(m.ratings, isEmpty);
      expect(m.technical, isEmpty);
      expect(m.actors, isEmpty);
      expect(m.genres, isEmpty);
      expect(m.tags, isEmpty);
      expect(m.rating, 0);
      expect(m.continueIndex, 0);
      expect(m.continueSeconds, 0);
    },
  );

  group('MediaDetail nested shapes', () {
    test('FileInfo carries index and name, which SPEC §3.3 omitted', () {
      final file = MediaDetail.fromJson(
        loadFixture('media_detail_directplay'),
      ).files.single;
      expect(file.index, const FileIndex(0));
      expect(file.name, '(2020) Direct Play Movie.mp4');
      expect(file.path, endsWith('.mp4'));
      expect(file.size, 42953);
      expect(file.season, 0);
      expect(file.episode, 0);
      expect(file.ext, '.mp4');
      expect(file.transcode, isFalse);
      expect(file.watched, isFalse);
      expect(file.subtitles.single.index, const SubtitleIndex(0));
      expect(file.subtitles.single.lang, 'en');
      expect(file.subtitles.single.label, 'English');
    });

    test('season and episode are non-zero on a multi-file item', () {
      final files = MediaDetail.fromJson(
        loadFixture('media_detail_transcode'),
      ).files;
      expect(files.map((f) => f.season), [1, 1]);
      expect(files.map((f) => f.episode), [1, 2]);
      expect(files.map((f) => f.index), [
        const FileIndex(0),
        const FileIndex(1),
      ]);
      expect(files.every((f) => f.transcode), isTrue);
      expect(files.every((f) => f.subtitles.isEmpty), isTrue);
    });

    test('a file with only an index decodes to documented defaults', () {
      final file = FileInfo.fromJson(const {'index': 3});
      expect(file.index, const FileIndex(3));
      expect(file.name, '');
      expect(file.path, '');
      expect(file.size, 0);
      expect(file.season, 0);
      expect(file.episode, 0);
      expect(file.ext, '');
      expect(file.transcode, isFalse);
      expect(file.watched, isFalse);
      expect(file.subtitles, isEmpty);
    });

    test('subtitles and pairs default rather than arriving null', () {
      expect(SubtitleInfo.fromJson(const {}).index, const SubtitleIndex(0));
      expect(SubtitleInfo.fromJson(const {}).lang, '');
      expect(SubtitleInfo.fromJson(const {}).label, '');
      expect(MetaPair.fromJson(const {}).key, '');
      expect(MetaPair.fromJson(const {}).value, '');
      expect(
        MetaPair.fromJson(const {'key': 'IMDb', 'value': '7.1/10'}).value,
        '7.1/10',
      );
    });

    test('watch state travels on the detail payload', () {
      final withState = MediaDetail.fromJson(
        loadFixture('media_detail_with_state'),
      );
      expect(withState.favorite, isTrue);
      expect(withState.rating, 8);
      expect(withState.continueSeconds, 2);

      final advanced = MediaDetail.fromJson(
        loadFixture('media_detail_multifile_advanced'),
      );
      expect(advanced.watched, isTrue);
      expect(advanced.continueIndex, 1);
      expect(advanced.files.every((f) => f.watched), isTrue);
    });
  });

  test('a list payload decodes element by element', () {
    final categories = loadFixtureList(
      'categories',
    ).map(Category.fromJson).toList();
    expect(categories.map((c) => c.id), [
      const CategoryId(1),
      const CategoryId(2),
    ]);

    final results = loadFixtureList(
      'search_results',
    ).map(MediaSummary.fromJson).toList();
    expect(results.single.title, 'Direct Play Movie');
    expect(loadFixtureList('search_empty').map(MediaSummary.fromJson), isEmpty);
  });

  test('copyWith replaces one field and leaves the rest alone', () {
    final detail = MediaDetail.fromJson(loadFixture('media_detail_directplay'));
    final renamed = detail.copyWith(title: 'Another Title');
    expect(renamed.title, 'Another Title');
    expect(renamed.files, detail.files);
    expect(renamed, isNot(detail));
    expect(detail.copyWith(), detail);

    final summary = MediaSummary.fromJson(
      loadFixtureList('search_results').first,
    );
    expect(summary.copyWith(watched: true).watched, isTrue);
    expect(summary.copyWith(watched: true).id, summary.id);

    final state = ServerState.fromJson(loadFixture('state'));
    expect(state.copyWith(version: '0.21.0').version, '0.21.0');
    expect(state.copyWith(needsSetup: true).needsSetup, isTrue);

    final auth = AuthResult.fromJson(loadFixture('me'));
    expect(auth.copyWith(alias: 'Tester').alias, 'Tester');
    expect(auth.copyWith(admin: false).admin, isFalse);
    expect(auth.copyWith(user: 'x').user, 'x');
    expect(auth.copyWith(mdlUsername: 'm').mdlUsername, 'm');
    expect(auth.copyWith(malUsername: 'a').malUsername, 'a');

    final category = Category.fromJson(loadFixtureList('categories').first);
    expect(category.copyWith(alias: 'Movies').alias, 'Movies');
    expect(
      category.copyWith(parentId: const CategoryId(9)).parentId,
      const CategoryId(9),
    );

    final rows = HomeRows.fromJson(loadFixture('home_populated'));
    expect(rows.copyWith(continueRow: const []).continueRow, isEmpty);
    expect(rows.copyWith(favorites: const []).completed, rows.completed);

    final file = detail.files.single;
    expect(file.copyWith(size: 1).size, 1);
    expect(file.copyWith(subtitles: const []).subtitles, isEmpty);
    expect(file.subtitles.single.copyWith(label: 'Deutsch').label, 'Deutsch');
    expect(detail.metadata.first.copyWith(value: 'x').value, 'x');
  });
}
