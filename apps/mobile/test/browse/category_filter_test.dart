import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/visible_rows.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tree's filter box and its sort button, as the pure function behind
/// them — no widget tree, because there is no widget in the answer.
void main() {
  Category cat(
    int id,
    String leaf, {
    int parent = 0,
    int media = 0,
    int position = 0,
  }) => Category(
    id: CategoryId(id),
    parentId: CategoryId(parent),
    leaf: leaf,
    name: leaf,
    media: media,
    position: position,
  );

  /// **Three roots whose three orders are all different**, which is what makes
  /// the sort cases mean anything: with two, or with equal `position`s, folder
  /// order and A–Z coincide and a button that did nothing would pass.
  final forest = buildCategoryTree([
    cat(1, 'Shows', position: 1, media: 5),
    cat(2, 'Anime', parent: 1, media: 31),
    cat(3, 'Films', position: 3, media: 20),
    cat(4, 'Anime films', parent: 3, media: 53),
    cat(5, 'Music', position: 2, media: 30),
  ]);

  List<String> leaves(List<VisibleRow> rows) => [
    for (final row in rows) row.node.category.leaf,
  ];

  test('with no filter it is the tree, collapsed', () {
    expect(leaves(visibleRows(forest, {})), ['Shows', 'Music', 'Films']);
  });

  test('an expanded node shows its children right under it', () {
    expect(leaves(visibleRows(forest, {const CategoryId(1)})), [
      'Shows',
      'Anime',
      'Music',
      'Films',
    ]);
  });

  /// **A filter answers with matches rather than with a shape**, which is the
  /// whole reason it is not a pruned tree: someone typing "anime" wants the two
  /// categories called that, not a hierarchy with the shape of them.
  test('a filter finds matches under COLLAPSED parents', () {
    // Nothing is expanded, so a pruned-tree implementation would show neither.
    expect(leaves(visibleRows(forest, {}, filter: 'anime')), [
      'Anime',
      'Anime films',
    ]);
  });

  test('a filter is case- and space-insensitive', () {
    expect(leaves(visibleRows(forest, {}, filter: '  ANIME ')), [
      'Anime',
      'Anime films',
    ]);
  });

  /// Every row a filter returns is flat and unexpandable, because there is no
  /// hierarchy on screen for a caret to open into.
  test('a filtered row never claims to be expanded', () {
    final rows = visibleRows(forest, {const CategoryId(1)}, filter: 'anime');

    expect(rows.every((r) => !r.expanded), isTrue);
  });

  test('a filter that matches nothing returns nothing', () {
    expect(visibleRows(forest, {}, filter: 'zzz'), isEmpty);
  });

  group('the sort button', () {
    test('cycles folder to A–Z to items and back', () {
      expect(CategorySort.folder.next, CategorySort.alphabetical);
      expect(CategorySort.alphabetical.next, CategorySort.mostItems);
      expect(CategorySort.mostItems.next, CategorySort.folder);
    });

    /// The default changes nothing: `position` then `name` is what
    /// `buildCategoryTree` already produced, and `position` is something the
    /// server was told deliberately.
    test('folder order is the order the tree arrived in', () {
      // The default, spelled out: an untouched button must change nothing.
      expect(CategorySort.values.first, CategorySort.folder);
      expect(leaves(visibleRows(forest, {})), ['Shows', 'Music', 'Films']);
    });

    test('A–Z sorts by leaf, not by the full path', () {
      expect(
        leaves(visibleRows(forest, {}, sort: CategorySort.alphabetical)),
        ['Films', 'Music', 'Shows'],
      );
    });

    test('items sorts fullest first', () {
      expect(
        leaves(visibleRows(forest, {}, sort: CategorySort.mostItems)),
        ['Music', 'Films', 'Shows'],
      );
    });

    test('the order reaches a filtered list too', () {
      expect(
        leaves(
          visibleRows(
            forest,
            {},
            filter: 'anime',
            sort: CategorySort.mostItems,
          ),
        ),
        ['Anime films', 'Anime'],
      );
    });

    /// Children are ordered by the same rule as roots. Asserted because
    /// sorting only the top level looks right on every one-deep library.
    test('it reaches an expanded node’s children as well', () {
      final deep = buildCategoryTree([
        cat(1, 'Shows'),
        cat(2, 'Zulu', parent: 1, media: 1),
        cat(3, 'Alpha', parent: 1, media: 9),
      ]);

      expect(
        leaves(
          visibleRows(
            deep,
            {const CategoryId(1)},
            sort: CategorySort.alphabetical,
          ),
        ),
        ['Shows', 'Alpha', 'Zulu'],
      );
    });

    /// The argument is a `CategoryNode.children` the caller does not own, so
    /// sorting it in place would reorder the tree itself for every later read.
    test('it never mutates the list it was given', () {
      final before = leaves(visibleRows(forest, {}));

      visibleRows(forest, {}, sort: CategorySort.mostItems);

      expect(leaves(visibleRows(forest, {})), before);
    });
  });
}
