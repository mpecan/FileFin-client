import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/visible_rows.dart';
import 'package:flutter_test/flutter_test.dart';

Category _cat(int id, {int parent = 0, String? name}) => Category(
  id: CategoryId(id),
  parentId: CategoryId(parent),
  leaf: name ?? 'c$id',
  name: name ?? 'c$id',
);

void main() {
  // 1 [ 2 [ 4 ], 3 ], 5
  final forest = buildCategoryTree([
    _cat(1),
    _cat(2, parent: 1),
    _cat(3, parent: 1, name: 'z3'),
    _cat(4, parent: 2),
    _cat(5),
  ]);

  List<int> ids(Set<CategoryId> expanded) => visibleRows(
    forest,
    expanded,
  ).map((r) => r.node.category.id.value).toList();

  test('nothing expanded shows the roots only', () {
    expect(ids(const {}), [1, 5]);
  });

  test(
    'expanding a root shows its children, in order, before the next root',
    () {
      expect(ids(const {CategoryId(1)}), [1, 2, 3, 5]);
    },
  );

  test('a grandchild appears only when BOTH ancestors are expanded', () {
    expect(ids(const {CategoryId(2)}), [1, 5], reason: 'parent is collapsed');
    expect(ids(const {CategoryId(1), CategoryId(2)}), [1, 2, 4, 3, 5]);
  });

  test('an expanded id that is not in the tree changes nothing', () {
    expect(ids(const {CategoryId(404)}), [1, 5]);
  });

  test('a row knows whether it can expand, and whether it is expanded', () {
    final rows = visibleRows(forest, const {CategoryId(1)});

    expect(rows.map((r) => r.node.category.id.value), [1, 2, 3, 5]);
    expect(rows[0].expandable, isTrue);
    expect(rows[0].expanded, isTrue);
    expect(rows[1].expandable, isTrue, reason: 'category 2 has a child');
    expect(rows[1].expanded, isFalse, reason: 'but it is collapsed');
    expect(rows[2].expandable, isFalse);
    expect(rows[3].expandable, isFalse);
  });

  test(
    'depth comes from the node, so indentation cannot drift from the tree',
    () {
      final rows = visibleRows(forest, const {CategoryId(1), CategoryId(2)});

      expect(rows.map((r) => r.node.depth), [0, 1, 2, 1, 0]);
    },
  );

  test('an empty forest is no rows', () {
    expect(visibleRows(const [], const {}), isEmpty);
  });

  test('a row prints its leaf and its state', () {
    expect(
      visibleRows(forest, const {CategoryId(1)}).first.toString(),
      'VisibleRow(c1, expanded: true)',
    );
  });
}
