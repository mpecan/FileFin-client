import 'package:filefin_core/filefin_core.dart';
import 'package:meta/meta.dart';

/// One row of the tree as the list actually draws it.
@immutable
class VisibleRow {
  /// A row for [node], at [node]'s own depth.
  const VisibleRow({required this.node, required this.expanded});

  /// The category and its children.
  final CategoryNode node;

  /// Whether this row's children are showing.
  final bool expanded;

  /// Whether it has any children to show.
  bool get expandable => node.children.isNotEmpty;

  @override
  String toString() => 'VisibleRow(${node.category.leaf}, expanded: $expanded)';
}

/// Flattens a forest into the rows a `ListView.builder` should draw.
///
/// **Flattened rather than nested, and that is what makes the list
/// virtualised.** Nested `Column`s inside an expanded tile build every
/// descendant on every frame whether or not it is on screen, so a large
/// library's category list would cost O(all categories) per frame — the exact
/// property NF2 rests on, in the one place people expect a tree to be nested.
/// A category list has no documented bound either (SPEC.md L2: nothing on this
/// server paginates).
///
/// Iterative rather than recursive for the same reason `buildCategoryTree` is:
/// the depth is whatever the server sent.
///
/// **A `for` over a list that grows as it is walked, not a `while` over a
/// stack**, and that is not style: `mutation_rules.xml` excludes a `while` body
/// up to its first closing brace, so the `if` below — the only branch here —
/// would never be mutated. The `for` exclusion covers the header alone, which
/// leaves the body in front of the gate.
///
/// Inserting children right after their parent is what makes the walk
/// depth-first. `insertAll` is O(n) each time, so the function is O(n²) in the
/// worst case; a category list is directories on a disk, and the alternative
/// loop shape costs more than the arithmetic saves.
List<VisibleRow> visibleRows(
  List<CategoryNode> forest,
  Set<CategoryId> expanded,
) {
  final rows = <VisibleRow>[];
  final pending = <CategoryNode>[...forest];
  for (var i = 0; i < pending.length; i += 1) {
    final node = pending[i];
    final isExpanded = expanded.contains(node.category.id);
    rows.add(VisibleRow(node: node, expanded: isExpanded));
    if (isExpanded) {
      pending.insertAll(i + 1, node.children);
    }
  }
  return rows;
}
