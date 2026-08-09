@Timeout(Duration(seconds: 60))
library;

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// `GET /api/search` against the real binary, and the properties F5's UI rests
/// on.
///
/// **Every one of these was wrong in the milestone brief or absent from this
/// repository's documentation until M6.0 measured it**, which is why they are
/// pinned against the live server rather than against a fixture we could
/// re-accept. A fixture proves the shape; only the binary proves the
/// behaviour, and the behaviour is what the screen's four renderings depend on.
///
/// Nothing here hard-codes a title, a year or an id. Everything is read out of
/// the live library first, so the suite says the same thing on a machine whose
/// seed was captured against and one whose was not.
void main() {
  late FileFinClient client;
  late MediaSummary film;

  setUp(() async {
    final server = await startServer();
    client = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(client.close);
    await client.login(seededCredentials);
    final categories = await client.categories();
    film = (await client.categoryMedia(
      categories.firstWhere((c) => c.leaf == 'Films').id,
    )).single;
  });

  List<String> idsOf(List<MediaSummary> rows) => [
    for (final row in rows) row.id.value,
  ];

  test('search is case-INSENSITIVE, in every scope that takes text', () async {
    // The brief said case-SENSITIVE and cited a measurement that is not
    // recorded anywhere in this repository. `db/search.go:52` builds every text
    // predicate as `LOWER(<col>) LIKE ? ESCAPE '\'` and `likePattern`
    // lowercases `q`, and eight live bodies agreed at M6.0/E-1.
    final word = film.title.split(' ').first;
    final variants = [
      word,
      word.toUpperCase(),
      word.toLowerCase(),
      _alternatingCase(word),
    ];

    for (final field in [SearchField.all, SearchField.title]) {
      final answers = [
        for (final q in variants) idsOf(await client.search(q, field: field)),
      ];
      expect(answers.first, contains(film.id.value));
      for (final answer in answers) {
        expect(answer, answers.first, reason: 'case changed the answer');
      }
    }
  });

  test('the match is a SUBSTRING, not a prefix and not a whole word', () async {
    // What makes a search box usable while it is being typed: the third
    // keystroke of a title has to find it.
    final title = film.title;
    final middle = title.substring(1, title.length - 1);

    final rows = await client.search(middle, field: SearchField.title);

    expect(idsOf(rows), contains(film.id.value));
  });

  test('LIKE wildcards are escaped, so % and _ are literal', () async {
    // The empties are the proof rather than an absence: an unescaped `%` would
    // match every row in the library and an unescaped `_` would match any title
    // with a character in it. `likePattern` escapes `\`, `%` and `_`, so a user
    // typing `100%` gets what they asked for.
    final everything = await client.search('', field: SearchField.title);
    expect(everything, isEmpty, reason: 'an empty q short-circuits to []');

    for (final q in ['%', '_', r'\', '100%']) {
      expect(
        await client.search(q, field: SearchField.title),
        isEmpty,
        reason: '$q matched something, so it was not escaped',
      );
    }

    // The other side of that boundary: one `_` replaced by the real character
    // does match, so the emptiness above is escaping rather than a broken
    // query.
    final oneOff = film.title.replaceRange(1, 2, '_');
    expect(await client.search(oneOff, field: SearchField.title), isEmpty);
    expect(
      idsOf(await client.search(film.title, field: SearchField.title)),
      contains(film.id.value),
    );
  });

  test('all eleven scopes are accepted and answer with a list', () async {
    // SPEC §3.2 listed seven. The vocabulary is eleven, and a scope the client
    // can send but the server rejects would be an error nobody sees until a
    // user picks it.
    for (final field in SearchField.values) {
      final rows = await client.search('a', field: field);
      expect(rows, isA<List<MediaSummary>>(), reason: field.wire);
    }
  });

  test('year is exact, and 0x7E4 is the one Atoi divergence (E-4)', () async {
    // `int.tryParse('0x7E4')` is 2020 and `strconv.Atoi` refuses it. Proven
    // live rather than inferred, because `0x7E4` *is* the film's year: an empty
    // answer here can only be a refusal.
    final year = film.year;
    expect(year, isNot(0), reason: 'the seeded film has a year to search for');

    expect(
      idsOf(await client.search('$year', field: SearchField.year)),
      contains(film.id.value),
    );
    expect(
      await client.search(
        '0x${year.toRadixString(16).toUpperCase()}',
        field: SearchField.year,
      ),
      isEmpty,
      reason: 'Atoi refuses a 0x prefix; int.tryParse would have accepted it',
    );
    expect(await client.search('nineteen', field: SearchField.year), isEmpty);
  });

  test('decade strips ONE trailing s, and the client knows it', () async {
    final decade = film.year - film.year % 10;

    expect(
      idsOf(await client.search('${decade}s', field: SearchField.decade)),
      contains(film.id.value),
    );
    expect(
      await client.search('${decade}ss', field: SearchField.decade),
      isEmpty,
      reason: 'TrimSuffix removes one occurrence, not every trailing s',
    );
  });

  test('searchIsRunnable never claims a query the server refuses', () async {
    // The differential check this suite exists for. `searchIsRunnable` is what
    // the screen uses to say "1990x is not a year" instead of showing an empty
    // library, so it must be false for every input the server declines to run
    // and true only for inputs it does run. The direction that matters is the
    // false one: a wrong `true` puts "No matches" over a query nobody ran.
    final year = film.year;
    final cases = <(String, SearchField)>[
      ('', SearchField.all),
      ('   ', SearchField.title),
      ('$year', SearchField.year),
      (' $year ', SearchField.year),
      ('+$year', SearchField.year),
      ('0x${year.toRadixString(16)}', SearchField.year),
      ('${year}x', SearchField.year),
      ('nineteen', SearchField.year),
      ('${year}e3', SearchField.year),
      ('99999999999999999999', SearchField.year),
      ('${year - year % 10}s', SearchField.decade),
      ('${year - year % 10}ss', SearchField.decade),
      ('nineties', SearchField.decade),
      (film.title, SearchField.title),
    ];

    for (final (q, field) in cases) {
      final runnable = searchIsRunnable(q, field: field);
      final rows = await client.search(q, field: field);
      if (!runnable) {
        expect(
          rows,
          isEmpty,
          reason: 'searchIsRunnable said no and the server ran "$q" anyway',
        );
      }
    }

    // And the one that proves the loop above is not vacuous: at least one case
    // is runnable AND returns the film, so "everything is empty" cannot pass.
    expect(
      idsOf(await client.search(film.title, field: SearchField.title)),
      contains(film.id.value),
    );
  });
}

/// `word` with every other character upper-cased, for the case-blindness check.
String _alternatingCase(String word) => [
  for (var i = 0; i < word.length; i++)
    i.isEven ? word[i].toUpperCase() : word[i].toLowerCase(),
].join();
