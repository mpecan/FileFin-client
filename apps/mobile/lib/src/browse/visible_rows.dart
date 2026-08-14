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

/// The three orders the tree's own sort button cycles through.
///
/// **`folder` is first and is the default, so an untouched button changes
/// nothing.** It is the order `buildCategoryTree` already produced — `position`
/// then `name` — and `position` is something the server was told deliberately.
/// A screen that silently re-alphabetised it would be discarding that.
enum CategorySort {
  /// The server's own order, which is what the tree arrives in.
  folder('Folder'),

  /// By leaf name, case-insensitively.
  alphabetical('A–Z'),

  /// Fullest first — how a person finds where their library actually is.
  mostItems('Items');

  const CategorySort(this.label);

  /// What the button says while this order is in force.
  final String label;

  /// The next order the button cycles to.
  CategorySort get next => values[(index + 1) % values.length];

  /// [nodes] in this order, as a new list — the argument is never mutated,
  /// because it is a `CategoryNode.children` the caller does not own.
  ///
  /// Private: `visibleRows` below is the only caller, and it is the function
  /// the screens and their tests actually go through (§5).
  List<CategoryNode> _sorted(List<CategoryNode> nodes) => switch (this) {
    folder => nodes,
    alphabetical =>
      [...nodes]..sort(
        (a, b) => a.category.leaf.toLowerCase().compareTo(
          b.category.leaf.toLowerCase(),
        ),
      ),
    mostItems =>
      [...nodes]..sort(
        (a, b) => b.category.media.compareTo(a.category.media),
      ),
  };
}

/// Flattens a forest into the rows a `ListView.builder` should draw.
///
/// **Flattened rather than nested, which is what makes the list virtualised**
/// (D14), and iterative rather than recursive: the depth is the server's.
///
/// **A `for` over a list that grows as it is walked, not a `while` over a
/// stack**: `mutation_rules.xml` excludes a `while` body, so the only branch
/// here would never be mutated.
///
/// **A non-empty [filter] answers with matches rather than with a shape**, and
/// every row is unexpandable at depth zero: someone typing "anime" wants the
/// two categories called that, not a hierarchy shaped like them.
List<VisibleRow> visibleRows(
  List<CategoryNode> forest,
  Set<CategoryId> expanded, {
  String filter = '',
  CategorySort sort = CategorySort.folder,
}) {
  final needle = filter.trim().toLowerCase();
  final rows = <VisibleRow>[];
  final matches = <CategoryNode>[];
  final pending = <CategoryNode>[...sort._sorted(forest)];
  for (var i = 0; i < pending.length; i += 1) {
    final node = pending[i];
    if (needle.isEmpty) {
      final isExpanded = expanded.contains(node.category.id);
      rows.add(VisibleRow(node: node, expanded: isExpanded));
      if (isExpanded) {
        pending.insertAll(i + 1, sort._sorted(node.children));
      }
    } else {
      // Every node is walked while filtering, expanded or not: a match hiding
      // under a collapsed parent is the one a filter exists to reach.
      pending.insertAll(i + 1, node.children);
      if (node.category.leaf.toLowerCase().contains(needle)) {
        matches.add(node);
      }
    }
  }
  if (needle.isEmpty) return rows;
  return [
    for (final node in sort._sorted(matches))
      VisibleRow(node: node, expanded: false),
  ];
}
