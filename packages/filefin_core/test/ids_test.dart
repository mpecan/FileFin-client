import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

/// The number of distinct members `xs` collapses to.
///
/// Written as a helper taking a parameter rather than as a set literal at the
/// call site: `equal_elements_in_set` rejects a literal whose duplication is
/// visible to the analyzer, and collapsing duplicates is exactly what these
/// tests are asserting.
int distinct(List<Object> xs) => xs.toSet().length;

void main() {
  group('MediaId', () {
    test('wraps its hex string and compares by value', () {
      expect(const MediaId('e4285edb34d5'), const MediaId('e4285edb34d5'));
      expect(
          const MediaId('e4285edb34d5'), isNot(const MediaId('919ac9caad25')));
      expect(const MediaId('e4285edb34d5').value, 'e4285edb34d5');
    });

    test('hashes by value, so it works as a Map key and a Set member', () {
      final seen = <MediaId, int>{const MediaId('a'): 1};
      seen[const MediaId('a')] = 2;
      expect(seen, hasLength(1));
      expect(seen[const MediaId('a')], 2);
      expect(
          distinct(
              [const MediaId('a'), const MediaId('a'), const MediaId('b')]),
          2);
    });

    test('prints its representation', () {
      expect(
          const MediaId('e4285edb34d5').toString(), contains('e4285edb34d5'));
    });
  });

  group('CategoryId', () {
    test('wraps an int64 category id and compares by value', () {
      expect(const CategoryId(1), const CategoryId(1));
      expect(const CategoryId(1), isNot(const CategoryId(2)));
      expect(const CategoryId(1).value, 1);
    });

    test('0 is the top-level parent sentinel, not null', () {
      expect(const CategoryId(0).value, 0);
      expect(const CategoryId(0), isNot(const CategoryId(1)));
    });

    test('hashes by value', () {
      expect(distinct([const CategoryId(7), const CategoryId(7)]), 1);
      expect(const CategoryId(7).hashCode, 7.hashCode);
    });
  });

  group('FileIndex', () {
    test('wraps a 0-based file index and compares by value', () {
      expect(const FileIndex(0), const FileIndex(0));
      expect(const FileIndex(0), isNot(const FileIndex(1)));
      expect(const FileIndex(3).value, 3);
    });

    test('hashes by value', () {
      expect(distinct([const FileIndex(2), const FileIndex(2)]), 1);
    });
  });

  group('SubtitleIndex', () {
    test('wraps a 0-based subtitle index and compares by value', () {
      expect(const SubtitleIndex(0), const SubtitleIndex(0));
      expect(const SubtitleIndex(0), isNot(const SubtitleIndex(1)));
      expect(const SubtitleIndex(1).value, 1);
    });

    test('hashes by value', () {
      expect(distinct([const SubtitleIndex(1), const SubtitleIndex(1)]), 1);
    });
  });

  test('IDs over different primitives never collide in one collection', () {
    // Two extension types over the SAME primitive erase to it, so equality
    // between them is that primitive's equality — the compiler, not a runtime
    // check, is what keeps a FileIndex out of a SubtitleIndex parameter. Dart
    // has no negative-compilation test framework, so nothing here can prove
    // that; STATE.md records the limitation. What a test CAN pin is that IDs
    // over different primitives stay distinct in a heterogeneous collection.
    expect(distinct([const CategoryId(1), const MediaId('1')]), 2);
    expect(distinct([const CategoryId(1), const FileIndex(1)]), 1);
  });
}
