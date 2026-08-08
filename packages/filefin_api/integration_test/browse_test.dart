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
    for (final category in categories.where((c) => c.leaf != 'Documentaries')) {
      expect(
        category.parentId,
        const CategoryId(0),
        reason: 'the two seeded root categories are top level, and 0 says so',
      );
      expect(category.id, isNot(const CategoryId(0)));
    }
  });

  test(
    'a nested category reports its parent, and the tree assembles',
    () async {
      // The seeded library was entirely flat until M3.2, so `buildCategoryTree`
      // — the whole of SPEC.md §3.2's client-side assembly — was proven against
      // fabricated rows and against nothing real. `tool/testserver/seed.sh` now
      // writes `Films/Documentaries/config.json` with a parentId, and this is
      // the assertion that a stock server actually honours it.
      final categories = await client.categories();
      final films = categories.firstWhere((c) => c.leaf == 'Films');
      final nested = categories.firstWhere((c) => c.leaf == 'Documentaries');

      expect(nested.parentId, films.id);

      final tree = buildCategoryTree(categories);

      expect(tree.map((n) => n.category.leaf), ['Films', 'Shows']);
      expect(tree.first.children.single.category.id, nested.id);
      expect(tree.first.children.single.depth, 1);
    },
  );

  test('name is the full path; leaf is what a tree row shows', () async {
    // Measured at M3.2, and it is the difference between a tree that reads
    // "Documentaries" under "Films" and one that reads "Films/Documentaries".
    final nested = (await client.categories()).firstWhere(
      (c) => c.leaf == 'Documentaries',
    );

    expect(nested.name, 'Films/Documentaries');
    expect(nested.leaf, 'Documentaries');
  });

  test(
    'an empty category reports zero counts, which is not "cache down"',
    () async {
      // `library.go:73-81` returns media/files as 0 when the cache is
      // unavailable too, so a UI cannot tell the two apart from these numbers.
      // The seeded nested category is genuinely empty, which is what makes the
      // ambiguity a captured fact rather than a note in a doc.
      final nested = (await client.categories()).firstWhere(
        (c) => c.leaf == 'Documentaries',
      );

      expect(nested.media, 0);
      expect(nested.files, 0);
      expect(nested.empty, isTrue);
      expect(await client.categoryMedia(nested.id), isEmpty);
    },
  );

  test('the seeded film has a poster, served back verbatim', () async {
    // The 200 branch of the poster route had no live coverage at all before
    // M3.3, and every captured payload said `hasPoster:false` — so a client
    // that never handled `true` looked perfectly healthy. `seed.sh` now copies
    // a committed `poster.jpg` into the film's folder.
    //
    // The assertion is byte-for-byte against the SAME committed file, which is
    // what makes it a contract test rather than a smoke test: it says
    // `http.ServeFile` hands the bytes back unmodified. It is reproducible for
    // the same reason — the input is a committed file, not a fresh encode.
    final films = (await client.categories()).firstWhere(
      (c) => c.leaf == 'Films',
    );
    final film = (await client.categoryMedia(films.id)).single;

    expect(film.hasPoster, isTrue);

    final bytes = await client.posterBytes(film.id);

    expect(bytes, isNotNull);
    expect(bytes, fixtureBytes('poster.jpg'));
  });

  test('an item with no poster answers null, not an error', () async {
    // docs/server-api.md: a 404 here is the normal answer for an un-enriched
    // library and must never surface as a failure. The show is deliberately
    // seeded without a poster so this branch has a real server behind it.
    final shows = (await client.categories()).firstWhere(
      (c) => c.leaf == 'Shows',
    );
    final show = (await client.categoryMedia(shows.id)).single;

    expect(show.hasPoster, isFalse);
    expect(await client.posterBytes(show.id), isNull);
  });

  test('the size hint never fails, even when no variant exists', () async {
    // `size` is a hint (`media.go:351`): the server serves the pre-built
    // variant when it exists and silently falls back otherwise. Nothing in the
    // seed builds variants, so this asserts the fallback rather than the
    // variant — which is the case a client actually has to survive.
    final films = (await client.categories()).firstWhere(
      (c) => c.leaf == 'Films',
    );
    final film = (await client.categoryMedia(films.id)).single;

    for (final size in PosterSize.values) {
      expect(await client.posterBytes(film.id, size: size), isNotNull);
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
