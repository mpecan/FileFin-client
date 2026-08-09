import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/search_field_labels.dart';
import 'package:filefin_mobile/src/browse/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

/// The query value and the four things the screen can say about it.
///
/// Plain `test()` throughout: nothing here imports a widget.
void main() {
  SearchOutcome outcome(
    String text, {
    SearchField field = SearchField.all,
    List<MediaSummary> results = const [],
  }) => SearchOutcome(
    query: SearchQuery(text: text, field: field),
    results: results,
  );

  const one = [MediaSummary(id: MediaId('aaaaaaaaaaaa'), title: 'Ada')];

  group('SearchQuery', () {
    test('an untouched query is a blank search of everything', () {
      const query = SearchQuery();

      expect(query.text, '');
      expect(query.field, SearchField.all);
      expect(query.isBlank, isTrue);
    });

    test('blankness is decided AFTER trimming, both sides of the boundary', () {
      expect(const SearchQuery(text: '   ').isBlank, isTrue);
      expect(const SearchQuery(text: ' a ').isBlank, isFalse);
    });

    test('what goes on the wire is trimmed', () {
      // The two numeric scopes TrimSpace before parsing and the nine text
      // scopes do not, so an untrimmed ' ada ' would search titles for a
      // string with spaces in it and find nothing.
      expect(const SearchQuery(text: '  ada  ').wireText, 'ada');
    });

    test('runnability is searchIsRunnable, scope by scope', () {
      expect(const SearchQuery(text: 'ada').isRunnable, isTrue);
      expect(
        const SearchQuery(text: '1994', field: SearchField.year).isRunnable,
        isTrue,
      );
      expect(
        const SearchQuery(text: 'nineteen', field: SearchField.year).isRunnable,
        isFalse,
      );
      expect(
        const SearchQuery(text: '1990s', field: SearchField.decade).isRunnable,
        isTrue,
      );
      expect(const SearchQuery(text: '  ').isRunnable, isFalse);
    });

    test('withText and withField each change exactly one half', () {
      const start = SearchQuery(text: 'ada', field: SearchField.director);

      expect(start.withText('grace').field, SearchField.director);
      expect(start.withText('grace').text, 'grace');
      expect(start.withField(SearchField.writer).text, 'ada');
      expect(start.withField(SearchField.writer).field, SearchField.writer);
    });

    test('two queries are never compared, so they are not comparable', () {
      // The `==`, `hashCode` and `toString` this class briefly had are gone
      // (§1): nothing in `apps/mobile/lib` compares two queries, and the
      // mutation gate proved the hash was untestable in consequence —
      // swapping `Object.hash`'s two arguments survived the whole suite,
      // because a hash consistent with an equality nobody calls cannot be
      // told from any other. Asserted here so that re-adding them is a
      // decision rather than a reflex.
      //
      // Built from a runtime string on purpose: two `const SearchQuery`s with
      // the same arguments are the SAME canonicalised instance, so a `const`
      // version of this would pass on identity and prove nothing.
      final text = ['a', 'd', 'a'].join();

      expect(SearchQuery(text: text) == SearchQuery(text: text), isFalse);
    });
  });

  group('the labels', () {
    test('every scope has a distinct picker label and a distinct noun', () {
      // Distinctness is the assertion that can fail: a copy-pasted arm gives
      // two scopes the same words and the picker becomes ambiguous, which no
      // "is it non-empty" check would notice.
      final labels = SearchField.values.map(searchFieldLabel).toSet();
      final nouns = SearchField.values.map(searchFieldNoun).toSet();

      expect(labels, hasLength(SearchField.values.length));
      expect(nouns, hasLength(SearchField.values.length));
      expect(searchFieldLabel(SearchField.all), 'Everything');
      expect(searchFieldLabel(SearchField.cast), 'Cast');
      expect(searchFieldNoun(SearchField.title), 'titles');
    });

    test('exactly the two numeric scopes have a unit', () {
      final withUnit = SearchField.values
          .where((f) => searchFieldNumericUnit(f) != null)
          .toList();

      expect(withUnit, [SearchField.year, SearchField.decade]);
      expect(searchFieldNumericUnit(SearchField.year), 'year');
      expect(searchFieldNumericUnit(SearchField.decade), 'decade');
      expect(searchFieldNumericUnit(SearchField.tag), isNull);
    });
  });

  group('searchNotice — the three ways a search shows nothing', () {
    test('a blank query invites one, naming the scope', () {
      expect(searchNotice(outcome('')), 'Type to search anything.');
      expect(
        searchNotice(outcome('   ', field: SearchField.director)),
        'Type to search directors.',
      );
    });

    test('an unparseable year says so, and does not say "no matches"', () {
      final notice = searchNotice(
        outcome('nineteen', field: SearchField.year),
      );

      expect(notice, contains('is not a year'));
      expect(notice, contains('nineteen'));
      expect(notice, isNot(contains('No matches')));
    });

    test('an unparseable decade says decade, not year', () {
      expect(
        searchNotice(outcome('nineties', field: SearchField.decade)),
        contains('is not a decade'),
      );
    });

    test('a RUNNABLE year with no rows says "no matches" instead', () {
      // The other side of the same boundary, and the case that kills the
      // mutant turning `&&` into `||`: 1994 parses, so the reason nothing came
      // back is that nothing matched.
      final notice = searchNotice(outcome('1994', field: SearchField.year));

      expect(notice, 'No matches for “1994” in years.');
    });

    test('a text scope never claims the input was unparseable', () {
      // The other operand of that `&&`: `title` has no unit, so however
      // unrunnable-looking the text is, the only honest answer is "no matches".
      expect(
        searchNotice(outcome('nineteen', field: SearchField.title)),
        'No matches for “nineteen” in titles.',
      );
    });

    test('the query is quoted TRIMMED, as it was sent', () {
      expect(
        searchNotice(outcome('  ada  ')),
        'No matches for “ada” in anything.',
      );
    });

    test('results mean there is nothing to say', () {
      expect(searchNotice(outcome('ada', results: one)), isNull);
    });

    test('a blank query with results still invites — it named no search', () {
      // Defensive about ordering rather than about reality: an outcome cannot
      // carry both today, and if one ever did, "Type to search" is the honest
      // caption for results nobody asked for.
      expect(searchNotice(outcome('', results: one)), startsWith('Type to'));
    });
  });
}
