@Timeout(Duration(seconds: 30))
library;

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// The browsing endpoints against the real binary (F4's data half).
///
/// The unit suite decodes committed fixtures, which proves the models match
/// what a server sent *once*. This proves they match what this server sends
/// *now* — the same check §8 asks the fixtures to keep honest, run against the
/// live thing rather than a recording of it.
void main() {
  late FileFinClient client;

  setUp(() async {
    final server = await startServer();
    client = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(client.close);
    await client.login(seededCredentials);
  });

  test('the seeded categories decode, with 0 meaning top level', () async {
    final categories = await client.categories();

    expect(categories.map((c) => c.leaf), containsAll(['Films', 'Shows']));
    for (final category in categories) {
      expect(
        category.parentId,
        const CategoryId(0),
        reason: 'both seeded categories are top level, and 0 says so',
      );
      expect(category.id, isNot(const CategoryId(0)));
    }
  });

  test('a category listing decodes into MediaSummary', () async {
    final categories = await client.categories();
    final films = categories.firstWhere((c) => c.leaf == 'Films');

    final media = await client.categoryMedia(films.id);

    expect(media, hasLength(1));
    expect(media.single.title, 'Direct Play Movie');
    expect(media.single.year, 2020);
    expect(media.single.id.value, hasLength(12), reason: '12 hex chars');
  });

  test('the two-file item carries both playback verdicts', () async {
    // The one thing the whole playback design turns on (SPEC.md §3.4): the
    // server tells us in advance whether a file is browser-native. The seed
    // builds one H.264 item and one HEVC item precisely so both answers appear.
    final categories = await client.categories();
    final shows = categories.firstWhere((c) => c.leaf == 'Shows');
    final films = categories.firstWhere((c) => c.leaf == 'Films');

    final show = await client.mediaDetail(
      (await client.categoryMedia(shows.id)).single.id,
    );
    final film = await client.mediaDetail(
      (await client.categoryMedia(films.id)).single.id,
    );

    expect(show.files, hasLength(2));
    expect(show.files.every((f) => f.transcode), isTrue);
    expect(show.files.map((f) => f.episode), [1, 2]);
    expect(film.files, hasLength(1));
    expect(film.files.single.transcode, isFalse);
    expect(film.files.single.season, 0, reason: '0 for a single-file item');

    // DECORRELATION, and it is the point of this test rather than a detail of
    // it. In the seeded library the transcoding item was also the watched one,
    // so `transcode: json['watched']` decoded every live payload correctly and
    // all nineteen integration tests stayed green. `FixtureRun` now writes the
    // opposite state into every copy, and these four lines are what makes the
    // substitution wrong in both directions at once.
    expect(show.files.every((f) => f.watched), isFalse);
    expect(film.files.single.watched, isTrue);
    expect(
      show.files.map((f) => f.transcode).toSet(),
      isNot(show.files.map((f) => f.watched).toSet()),
      reason: "transcode is the server's codec verdict; watched is user state",
    );
  });

  test('files[].path is RELATIVE to the data dir, as documented', () async {
    // `relTo(dataDir, f.Path)` returns the row unchanged when it is not under
    // `dataDir`, and the cache stores absolute paths — so a copied library that
    // still pointed at the seed answered `files[].path` ABSOLUTE, diverging
    // from `media_detail_directplay.json` and from `docs/server-api.md` without
    // one test noticing. M3's playback work reads this field.
    final categories = await client.categories();
    final films = categories.firstWhere((c) => c.leaf == 'Films');
    final detail = await client.mediaDetail(
      (await client.categoryMedia(films.id)).single.id,
    );

    final path = detail.files.single.path;
    expect(path, isNot(startsWith('/')));
    expect(path, 'Films/(2020) Direct Play Movie/(2020) Direct Play Movie.mp4');
  });

  test('the rich metadata blocks survive the round trip (§8)', () async {
    final categories = await client.categories();
    final films = categories.firstWhere((c) => c.leaf == 'Films');
    final detail = await client.mediaDetail(
      (await client.categoryMedia(films.id)).single.id,
    );

    expect(detail.genres, isNotEmpty);
    expect(detail.tags, contains('direct-play'));
    expect(detail.actors, contains('Ada Lovelace'));
    // `key` is a display label, not a stable identifier: unlisted meta.json
    // keys fall through under their raw name. The seed plants `customKey` to
    // keep the client from keying off these.
    expect(detail.metadata.map((p) => p.key), contains('customKey'));
    expect(detail.files.single.subtitles, hasLength(1));
  });

  test('an unknown media id is a real 404, not the SPA catch-all', () async {
    // The handler matched and found nothing, which is a different thing from
    // an unrouted path — and the only reason a client can tell them apart is
    // that this one really is a 404.
    await expectLater(
      client.mediaDetail(const MediaId('ffffffffffff')),
      throwsA(isA<NotFound>()),
    );
  });

  test('a media id the server could never have sent never leaves', () async {
    await expectLater(
      client.mediaDetail(const MediaId('')),
      throwsA(isA<MalformedIdentifier>()),
    );
  });
}
