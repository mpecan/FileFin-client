/// `SearchField` and `searchIsRunnable`.
///
/// Every row in the numeric tables below was **measured against the real
/// binary** at v0.20.3 (M6.0/E-4), not derived from `strconv`'s documentation:
/// each input was sent to `GET /api/search` in both numeric scopes and the row
/// count recorded. Where an input's numeric value could not distinguish
/// "rejected" from "parsed but nothing matched", the input was chosen so that
/// it could — `0x7E4` *is* 2020, so `[]` from `field=year` can only mean the
/// server refused to read it.
library;

import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

void main() {
  group('SearchField — eleven scopes, and the wire word for each', () {
    test('there are eleven, and SPEC §3.2 used to list seven', () {
      expect(SearchField.values, hasLength(11));
    });

    test('every wire token is the enum name', () {
      expect(
        SearchField.values.map((f) => f.wire).toList(),
        [
          'all',
          'year',
          'decade',
          'title',
          'description',
          'cast',
          'genre',
          'tag',
          'language',
          'director',
          'writer',
        ],
      );
    });

    test('the wire word for the actor facet is cast, not actor', () {
      expect(SearchField.cast.wire, 'cast');
    });
  });

  group('searchIsRunnable — a blank query never reaches the network', () {
    test('an empty query is not runnable in any scope', () {
      for (final field in SearchField.values) {
        expect(searchIsRunnable('', field: field), isFalse, reason: '$field');
      }
    });

    test('a whitespace-only query is not runnable either', () {
      // The server trims before its own empty check (`search.go:21`,
      // `db/search.go:17`), so "   " is the empty query with extra steps.
      for (final field in SearchField.values) {
        expect(
          searchIsRunnable('   ', field: field),
          isFalse,
          reason: '$field',
        );
      }
    });

    test('any non-empty text is runnable in every non-numeric scope', () {
      const text = ['a', 'Kurosawa', '%', '_', '100%', 'nineteen ninety'];
      for (final field in SearchField.values) {
        if (field == SearchField.year || field == SearchField.decade) continue;
        for (final q in text) {
          expect(
            searchIsRunnable(q, field: field),
            isTrue,
            reason: '$field $q',
          );
        }
      }
    });
  });

  group('searchIsRunnable — year mirrors strconv.Atoi, measured live', () {
    const runnable = [
      '2020',
      '02020',
      '+2020',
      '-2020',
      ' 2020 ',
      '2020 ',
      '9223372036854775807',
      '-9223372036854775808',
    ];
    const refused = [
      '2020s',
      '2020S',
      '2020ss',
      '20 20',
      '2e3',
      '2_020',
      '٢٠٢٠',
      '2020.0',
      's',
      '+',
      '-',
      '0b11111100100',
      '9223372036854775808',
      '-9223372036854775809',
      '99999999999999999999',
    ];

    for (final q in runnable) {
      test('year runs "$q"', () {
        expect(searchIsRunnable(q, field: SearchField.year), isTrue);
      });
    }
    for (final q in refused) {
      test('year refuses "$q"', () {
        expect(searchIsRunnable(q, field: SearchField.year), isFalse);
      });
    }

    test('the 0x prefix is refused, and it is the ONE divergence', () {
      // `int.tryParse` honours `0x`; `strconv.Atoi` does not. Proven live
      // rather than read off the source: `0x7E4` is 2020, and
      // `field=year&q=0x7E4` came back `[]` from v0.20.3 where `q=2020`
      // returned the row. Both spellings, because Dart accepts both.
      expect(int.tryParse('0x7E4'), 2020, reason: 'the trap this guards');
      expect(searchIsRunnable('0x7E4', field: SearchField.year), isFalse);
      expect(searchIsRunnable('0X7E4', field: SearchField.year), isFalse);
      expect(searchIsRunnable('0x7c6', field: SearchField.decade), isFalse);
    });

    test('the 64-bit boundary is where Go and Dart agree exactly', () {
      expect(
        searchIsRunnable('9223372036854775807', field: SearchField.year),
        isTrue,
      );
      expect(
        searchIsRunnable('9223372036854775808', field: SearchField.year),
        isFalse,
      );
    });
  });

  group('searchIsRunnable — decade strips ONE trailing s, after lowering', () {
    const runnable = ['1990s', '1990S', '1990', ' 1990s ', '+1990s', '-1990s'];
    const refused = ['1990ss', 's', 'S', 'nineteen', '199o', '0x7c6'];

    for (final q in runnable) {
      test('decade runs "$q"', () {
        expect(searchIsRunnable(q, field: SearchField.decade), isTrue);
      });
    }
    for (final q in refused) {
      test('decade refuses "$q"', () {
        expect(searchIsRunnable(q, field: SearchField.decade), isFalse);
      });
    }

    test('the suffix rule is decade-only — year refuses the same input', () {
      // `TrimSuffix` lives in the `decade` arm alone (`db/search.go:43`), and
      // the live measurement shows it: `q=2020s&field=year` returned no rows
      // while `q=2020s&field=decade` returned one.
      expect(searchIsRunnable('1990s', field: SearchField.decade), isTrue);
      expect(searchIsRunnable('1990s', field: SearchField.year), isFalse);
    });
  });
}
