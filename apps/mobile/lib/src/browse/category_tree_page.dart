import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/visible_rows.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';

/// F4's first screen: the category tree, assembled client-side.
class CategoryTreePage extends StatefulWidget {
  /// Browses [api]'s categories; [onOpen] opens one.
  const CategoryTreePage({
    required this.api,
    required this.title,
    required this.onOpen,
    this.onSignIn,
    super.key,
  });

  /// Where the categories come from.
  final LibraryApi api;

  /// The app-bar title — the saved server's name.
  final String title;

  /// Opens a category as a poster grid.
  final void Function(Category category) onOpen;

  /// Where a `SessionExpired` sends the user (F3's last resort).
  final VoidCallback? onSignIn;

  @override
  State<CategoryTreePage> createState() => _CategoryTreePageState();
}

class _CategoryTreePageState extends State<CategoryTreePage> {
  late final AsyncController<List<CategoryNode>> _controller =
      AsyncController<List<CategoryNode>>(
        (token) async =>
            buildCategoryTree(await widget.api.categories(cancelToken: token)),
      );

  final _expanded = <CategoryId>{};

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: AsyncView<List<CategoryNode>>(
      controller: _controller,
      onSignIn: widget.onSignIn,
      builder: (context, forest) {
        if (forest.isEmpty) return const _EmptyLibrary();
        final rows = visibleRows(forest, _expanded);
        // ListView.builder over a FLATTENED list. A nested tree of Columns
        // builds every descendant on every frame whether or not it is on
        // screen, and a category list has no documented bound either
        // (SPEC.md L2 — nothing on this server paginates).
        return ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) => CategoryRow(
            row: rows[index],
            onOpen: () => widget.onOpen(rows[index].node.category),
            onToggle: rows[index].expandable
                ? () => setState(() {
                    final id = rows[index].node.category.id;
                    if (!_expanded.remove(id)) _expanded.add(id);
                  })
                : null,
          ),
        );
      },
    ),
  );
}

/// A library with no categories at all.
///
/// An empty state, not a forever-spinner. A freshly installed server really
/// does have nothing in it, and a spinner would say "wait" about something
/// that is never going to arrive.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'This server has no categories yet. Categories are the top-level '
        'folders in its media directory.',
        textAlign: TextAlign.center,
      ),
    ),
  );
}

/// One row of the tree.
class CategoryRow extends StatelessWidget {
  /// Draws [row], indenting it by its depth.
  const CategoryRow({
    required this.row,
    required this.onOpen,
    this.onToggle,
    super.key,
  });

  /// The node and its expansion state.
  final VisibleRow row;

  /// Opens this category.
  final VoidCallback onOpen;

  /// Expands or collapses it, or null when it has no children.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final category = row.node.category;
    return ListTile(
      contentPadding: EdgeInsets.only(
        left: 16.0 + row.node.depth * 20,
        right: 8,
      ),
      // `leaf`, never `name`. `name` is the FULL PATH — a nested category
      // reads "Films/Documentaries" — which would print the whole path on a
      // row already sitting under its parent. Captured at M3.2 against the
      // real server rather than taken from the doc.
      title: Text(category.leaf),
      subtitle: Text(_counts(category)),
      onTap: onOpen,
      trailing: onToggle == null
          ? null
          : IconButton(
              icon: Icon(row.expanded ? Icons.expand_less : Icons.expand_more),
              tooltip: row.expanded ? 'Collapse' : 'Expand',
              onPressed: onToggle,
            ),
    );
  }

  /// The counts, worded so 0 does not read as "empty".
  ///
  /// `library.go:73-81` returns `media` and `files` as **0 when the cache is
  /// unavailable**, exactly as it does for a genuinely empty category. A client
  /// cannot tell them apart from these numbers, so a row that said "0 items"
  /// would state as a fact something it does not know. Saying nothing about
  /// the contents is the honest rendering.
  static String _counts(Category category) {
    if (category.media == 0 && category.files == 0) return 'No items listed';
    final items = category.media == 1 ? '1 item' : '${category.media} items';
    final files = category.files == 1 ? '1 file' : '${category.files} files';
    return '$items · $files';
  }
}
