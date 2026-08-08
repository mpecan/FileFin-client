/// `GET /api/categories` returns a FLAT list; SPEC.md §3.2 says the tree is
/// assembled client-side. That assembly is deterministic and I/O-free, so it
/// lives here rather than in a widget — this is where `dart test`, the mutation
/// gate and `kiri_check` can all reach it.
///
/// The seed is fixed for the same reason `resume_properties_test.dart` fixes
/// its own: `just mutants` runs the suite once per mutant, and a generator that
/// draws a different sample each run turns a surviving mutant into a coin flip.
library;

import 'package:filefin_core/filefin_core.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

Category _cat(
  int id, {
  int parent = 0,
  String name = '',
  int position = 0,
}) => Category(
  id: CategoryId(id),
  parentId: CategoryId(parent),
  name: name.isEmpty ? 'c$id' : name,
  position: position,
);

/// Every category in the tree, depth-first, as its raw id.
List<int> _flatten(List<CategoryNode> nodes) => [
  for (final node in nodes) ...[
    node.category.id.value,
    ..._flatten(node.children),
  ],
];

/// The ids of one level, in the order the tree presents them.
List<int> _ids(List<CategoryNode> nodes) => [
  for (final node in nodes) node.category.id.value,
];

void main() {
  KiriCheck.seed = 20260808;

  group('against real captured bytes', () {
    List<Category> seeded() => [
      for (final json in loadFixtureList('categories')) Category.fromJson(json),
    ];

    test('the seeded library assembles into two roots, one with a child', () {
      final tree = buildCategoryTree(seeded());

      expect(_ids(tree), [1, 2]);
      expect(_flatten(tree), [1, 3, 2]);
      expect(_ids(tree.first.children), [3]);
      expect(tree.last.children, isEmpty);
    });

    test('the nested category is one deeper, from a real parentId', () {
      // Measured against the real binary at v0.20.3 before this test existed:
      // a directory inside a category directory, with its own config.json
      // carrying `parentId`, becomes a category with that parentId. Until then
      // the seeded library was entirely flat and every nesting assertion in
      // this file stood on fabricated rows (§8).
      final nested = seeded().firstWhere(
        (c) => c.parentId != const CategoryId(0),
      );

      final tree = buildCategoryTree(seeded());

      expect(nested.parentId, const CategoryId(1));
      expect(tree.first.children.single.depth, 1);
      expect(tree.first.children.single.category.id, nested.id);
    });

    test('`name` is the full path and `leaf` is what a tree row shows', () {
      // A tree rendering `name` would print "Films/Documentaries" on a row
      // sitting under "Films". Only a nested capture can show that at all.
      final tree = buildCategoryTree(seeded());
      final child = tree.first.children.single.category;

      expect(child.name, 'Films/Documentaries');
      expect(child.leaf, 'Documentaries');
      expect(tree.first.category.name, tree.first.category.leaf);
    });
  });

  group('parentId 0 is the top-level sentinel, not "absent"', () {
    test('a category whose parentId is 0 is a root', () {
      final tree = buildCategoryTree([_cat(7)]);

      expect(_ids(tree), [7]);
      expect(tree.single.depth, 0);
    });

    test("a category whose parentId names another is that one's child", () {
      final tree = buildCategoryTree([_cat(1), _cat(2, parent: 1)]);

      expect(_ids(tree), [1]);
      expect(_ids(tree.single.children), [2]);
      expect(tree.single.children.single.depth, 1);
    });

    test('depth counts links, not levels seen so far', () {
      final tree = buildCategoryTree([
        _cat(1),
        _cat(2, parent: 1),
        _cat(3, parent: 2),
        _cat(4, parent: 3),
      ]);

      expect(_flatten(tree), [1, 2, 3, 4]);
      expect(
        tree.single.children.single.children.single.children.single.depth,
        3,
      );
    });

    test('a parent declared AFTER its child still adopts it', () {
      // The server orders the flat list by its own rules, not ours, and
      // nothing in `library.go` promises a parent precedes its children.
      final tree = buildCategoryTree([_cat(2, parent: 1), _cat(1)]);

      expect(_ids(tree), [1]);
      expect(_ids(tree.single.children), [2]);
    });
  });

  group('siblings order by position, then name', () {
    test('position wins', () {
      final tree = buildCategoryTree([
        _cat(1, position: 2, name: 'aaa'),
        _cat(2, position: 1, name: 'zzz'),
      ]);

      expect(_ids(tree), [2, 1]);
    });

    test('name breaks a tie on position', () {
      final tree = buildCategoryTree([
        _cat(1, name: 'zebra'),
        _cat(2, name: 'aardvark'),
      ]);

      expect(_ids(tree), [2, 1]);
    });

    test('input order breaks a tie on both, so the result is stable', () {
      // Dart's List.sort is NOT documented stable, so a comparator that
      // returns 0 for two rows leaves their order to the implementation. The
      // third key is what makes this function answer the same way twice — and
      // `just mutants` runs the suite once per mutant, so an answer that moves
      // is a gate that flaps.
      final tree = buildCategoryTree([
        _cat(9, name: 'same'),
        _cat(4, name: 'same'),
      ]);

      expect(_ids(tree), [9, 4]);
    });

    test('children are ordered too, not only roots', () {
      final tree = buildCategoryTree([
        _cat(1),
        _cat(2, parent: 1, position: 5),
        _cat(3, parent: 1, position: 1),
      ]);

      expect(_ids(tree.single.children), [3, 2]);
    });
  });

  group('an orphan surfaces, it is never dropped (G5)', () {
    test('a parentId naming an absent category becomes a root', () {
      final tree = buildCategoryTree([_cat(1), _cat(2, parent: 404)]);

      expect(_flatten(tree)..sort(), [1, 2]);
    });

    test('an orphan keeps its own children', () {
      final tree = buildCategoryTree([
        _cat(2, parent: 404),
        _cat(3, parent: 2),
      ]);

      expect(_ids(tree), [2]);
      expect(_ids(tree.single.children), [3]);
    });

    test('an orphan sorts among the real roots rather than after them', () {
      final tree = buildCategoryTree([
        _cat(1, position: 5),
        _cat(2, parent: 404, position: 1),
      ]);

      expect(_ids(tree), [2, 1]);
    });
  });

  group('a cycle terminates and loses nobody', () {
    test('a two-node cycle produces both nodes, exactly once', () {
      final tree = buildCategoryTree([
        _cat(1, parent: 2),
        _cat(2, parent: 1),
      ]);

      expect(_flatten(tree)..sort(), [1, 2]);
    });

    test('a three-node cycle produces all three, exactly once', () {
      final tree = buildCategoryTree([
        _cat(1, parent: 2),
        _cat(2, parent: 3),
        _cat(3, parent: 1),
      ]);

      expect(_flatten(tree)..sort(), [1, 2, 3]);
    });

    test('exactly one link is cut, so the rest of the shape survives', () {
      // The first index in input order that lies on a cycle is the one cut
      // loose. Breaking every link on the cycle would be simpler and would
      // throw away real structure the server sent.
      final tree = buildCategoryTree([
        _cat(1, parent: 2),
        _cat(2, parent: 1),
      ]);

      expect(_ids(tree), [1]);
      expect(_ids(tree.single.children), [2]);
    });

    test('a category that is its own parent becomes a root', () {
      final tree = buildCategoryTree([_cat(1, parent: 1)]);

      expect(_ids(tree), [1]);
      expect(tree.single.children, isEmpty);
    });

    test('a category hanging BELOW a cycle stays attached to it', () {
      final tree = buildCategoryTree([
        _cat(1, parent: 2),
        _cat(2, parent: 1),
        _cat(3, parent: 2),
      ]);

      expect(_flatten(tree)..sort(), [1, 2, 3]);
      expect(_flatten(tree), [1, 2, 3]);
    });
  });

  group('a duplicate id does not duplicate a subtree', () {
    test('both rows appear, and the child attaches to exactly one', () {
      final tree = buildCategoryTree([
        _cat(1, name: 'first'),
        _cat(1, name: 'second'),
        _cat(2, parent: 1),
      ]);

      expect(_flatten(tree), [1, 2, 1]);
      expect(_ids(tree), [1, 1]);
      expect(tree.first.category.name, 'first');
      expect(_ids(tree.first.children), [2]);
      expect(tree.last.children, isEmpty);
    });
  });

  test('a node prints its id, depth and child count, and no more', () {
    // It appears in every `expect` failure this file can produce, so it is a
    // debugging tool rather than decoration — and an untested one would be an
    // uncovered line against a ratchet of 0.
    final tree = buildCategoryTree([_cat(1), _cat(2, parent: 1)]);

    expect(tree.single.toString(), 'CategoryNode(1, depth 0, 1 child(ren))');
    expect(
      tree.single.children.single.toString(),
      'CategoryNode(2, depth 1, 0 child(ren))',
    );
  });

  test('an empty list is an empty forest, not an error', () {
    expect(buildCategoryTree([]), isEmpty);
  });

  group('properties', () {
    property('every input category appears exactly once', () {
      forAll(_graphs, (graph) {
        final flat = _categoriesOf(graph);

        final seen = _flatten(buildCategoryTree(flat));

        expect(seen.length, flat.length);
        expect(seen..sort(), flat.map((c) => c.id.value).toList()..sort());
      });
    });

    property('no node is its own ancestor', () {
      forAll(_graphs, (graph) {
        final tree = buildCategoryTree(_categoriesOf(graph));

        expect(_deepestSelfReference(tree, const []), isNull);
      });
    });

    property('a child is always exactly one deeper than its parent', () {
      forAll(_graphs, (graph) {
        final tree = buildCategoryTree(_categoriesOf(graph));

        expect(_depthBreak(tree, 0), isNull);
      });
    });
  });
}

/// A random parent graph: `parents[i]` is the parentId of the category with
/// id `i + 1`. Drawing from a range that overlaps the id space and overshoots
/// it produces top-level rows (0), real edges, orphans and cycles all from one
/// generator — the four cases the tree builder has to survive.
final Arbitrary<List<int>> _graphs = list(
  integer(min: 0, max: 9),
  minLength: 0,
  maxLength: 7,
);

List<Category> _categoriesOf(List<int> parents) => [
  for (var i = 0; i < parents.length; i++)
    Category(
      id: CategoryId(i + 1),
      parentId: CategoryId(parents[i]),
      name: 'c${i + 1}',
      position: parents[i],
    ),
];

/// The first id that appears among its own ancestors, or null if none does.
int? _deepestSelfReference(List<CategoryNode> nodes, List<int> ancestors) {
  for (final node in nodes) {
    final id = node.category.id.value;
    if (ancestors.contains(id)) return id;
    final deeper = _deepestSelfReference(node.children, [...ancestors, id]);
    if (deeper != null) return deeper;
  }
  return null;
}

/// The first id whose `depth` is not the depth it actually sits at.
int? _depthBreak(List<CategoryNode> nodes, int expected) {
  for (final node in nodes) {
    if (node.depth != expected) return node.category.id.value;
    final deeper = _depthBreak(node.children, expected + 1);
    if (deeper != null) return deeper;
  }
  return null;
}
