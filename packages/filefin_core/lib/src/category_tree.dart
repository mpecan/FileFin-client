import 'package:filefin_core/src/models/category.dart';
import 'package:meta/meta.dart';

/// One category and the categories beneath it.
///
/// The server has no tree endpoint: `GET /api/categories` returns a flat list
/// with a `parentId` on each row (SPEC.md §3.2, `library.go:27-42`), and the
/// assembly is the client's job. Doing it here rather than in a widget is what
/// puts it in front of `dart test`, the mutation gate and `kiri_check`.
@immutable
class CategoryNode {
  /// A node holding [category], its [children] and its [depth].
  const CategoryNode({
    required this.category,
    required this.children,
    required this.depth,
  });

  /// The row exactly as the server sent it.
  final Category category;

  /// Its direct children, already ordered.
  final List<CategoryNode> children;

  /// How many links separate it from a root. A root is 0.
  ///
  /// Carried on the node rather than recomputed by the UI: a `ListView` over a
  /// flattened, expansion-aware list has no parent to ask, and nested `Column`s
  /// — which would have one — defeat virtualisation (SPEC.md L2).
  final int depth;

  @override
  String toString() =>
      'CategoryNode(${category.id.value}, depth $depth, '
      '${children.length} child(ren))';
}

/// `parentId == 0` means **top level**, not "absent" (`library.go:29`).
const _topLevel = 0;

/// Assembles [flat] into a forest, losing nothing and terminating always.
///
/// Four inputs a naive `parentId` lookup gets wrong, and the rule for each:
/// **`parentId == 0`** is the top-level sentinel; an **orphan** surfaces at top
/// level rather than being dropped (G5); a **cycle** loses no row — the first
/// index in input order lying on one is cut loose and becomes a root, breaking
/// exactly one link per cycle; a **duplicate id** attaches children to the
/// first row only, so both rows appear and only one parents anything.
///
/// Siblings order by `position`, then `name`, **then input order** — the third
/// key is not decoration: Dart's `List.sort` is not documented stable, and an
/// answer that moves between runs is a gate that flaps.
List<CategoryNode> buildCategoryTree(List<Category> flat) {
  final count = flat.length;

  // First occurrence wins. This is the whole duplicate-id rule.
  final firstIndexOfId = <int, int>{};
  for (var i = 0; i < count; i++) {
    firstIndexOfId.putIfAbsent(flat[i].id.value, () => i);
  }

  final parentIndex = List<int?>.filled(count, null);
  for (var i = 0; i < count; i++) {
    final parentId = flat[i].parentId.value;
    if (parentId == _topLevel) continue;
    final at = firstIndexOfId[parentId];
    if (at == null) continue;
    if (at == i) continue;
    parentIndex[i] = at;
  }

  // Cut one link per cycle. Written against the LIVE array rather than a
  // snapshot, deliberately: once the first member is cut loose the rest of that
  // cycle no longer walks in a circle, so no further link is broken.
  for (var i = 0; i < count; i++) {
    if (_liesOnACycle(i, parentIndex)) {
      parentIndex[i] = null;
    }
  }

  final depths = List<int>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    depths[i] = _depthOf(i, parentIndex);
  }

  final rootIndices = <int>[];
  final childIndices = List.generate(count, (_) => <int>[], growable: false);
  for (var i = 0; i < count; i++) {
    final parent = parentIndex[i];
    if (parent == null) {
      rootIndices.add(i);
    } else {
      childIndices[parent].add(i);
    }
  }

  int order(int a, int b) {
    final byPosition = flat[a].position.compareTo(flat[b].position);
    if (byPosition != 0) return byPosition;
    final byName = flat[a].name.compareTo(flat[b].name);
    if (byName != 0) return byName;
    return a.compareTo(b);
  }

  rootIndices.sort(order);
  for (final children in childIndices) {
    children.sort(order);
  }

  // Deepest first, so every child exists before its parent asks for it.
  // Iterative rather than recursive: a server sending a 5000-link chain would
  // otherwise overflow the stack, and a category list has no documented bound
  // (SPEC.md L2 — nothing on this server paginates).
  final byDepth = [for (var i = 0; i < count; i++) i]
    ..sort((a, b) => depths[b].compareTo(depths[a]));
  final built = List<CategoryNode?>.filled(count, null);
  for (final i in byDepth) {
    built[i] = CategoryNode(
      category: flat[i],
      children: [for (final child in childIndices[i]) built[child]!],
      depth: depths[i],
    );
  }

  return [for (final i in rootIndices) built[i]!];
}

/// Does the parent chain above [index] come back to [index] itself?
///
/// A chain that runs past the number of categories without returning to
/// [index] and without reaching a root contains a cycle that [index] is not
/// part of — it hangs *below* one. That is not a link worth cutting: the cycle
/// itself is cut when its own first member is reached.
bool _liesOnACycle(int index, List<int?> parentIndex) {
  var cursor = parentIndex[index];
  for (var step = 0; step < parentIndex.length; step++) {
    if (cursor == null) return false;
    if (cursor == index) return true;
    cursor = parentIndex[cursor];
  }
  return false;
}

/// How many links separate [index] from its root.
///
/// The step limit is a termination guarantee, not a fallback: every cycle has
/// already been cut by the time this runs, so the walk reaches a root on its
/// own — and the bound is what keeps that true from three functions away
/// rather than by trust. It deliberately has no "gave up" return value,
/// because a value nothing can produce is a line no test can cover (§1) and
/// coverage said so.
int _depthOf(int index, List<int?> parentIndex) {
  var depth = 0;
  var cursor = parentIndex[index];
  for (var step = 0; step < parentIndex.length; step++) {
    if (cursor == null) break;
    depth += 1;
    cursor = parentIndex[cursor];
  }
  return depth;
}
