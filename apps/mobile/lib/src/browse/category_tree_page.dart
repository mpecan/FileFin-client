import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/library_actions.dart';
import 'package:filefin_mobile/src/browse/visible_rows.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';

/// F4's first screen: the category tree, assembled client-side.
class CategoryTreePage extends StatefulWidget {
  /// Browses [api]'s categories; [onOpen] opens one.
  const CategoryTreePage({
    required this.api,
    required this.title,
    required this.onOpen,
    this.onSignIn,
    this.onSearch,
    this.onServers,
    this.onSettings,
    this.onSignOut,
    super.key,
  });

  /// Where the categories come from.
  final LibraryApi api;

  /// The header title — the saved server's name.
  final String title;

  /// Opens a category as a poster grid.
  final void Function(Category category) onOpen;

  /// Where a `SessionExpired` sends the user (F3's last resort).
  final VoidCallback? onSignIn;

  /// Selects the Search destination.
  final VoidCallback? onSearch;

  /// Opens F11's server picker.
  final VoidCallback? onServers;

  /// Opens the playback settings sheet.
  ///
  /// This screen is the only one signed in to a server and above every other,
  /// which is what makes it the place `wifiOnly` and `allowUnverifiedPlayback`
  /// become reachable — both are refusals `decide()` can return and neither had
  /// a way in before M4.8.
  final VoidCallback? onSettings;

  /// Ends the session and forgets this account (F2, §9).
  final VoidCallback? onSignOut;

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
  var _filter = '';
  CategorySort _sort = CategorySort.folder;

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
    appBar: LibraryHeader(
      title: widget.title,
      onServers: widget.onServers,
      onSearch: widget.onSearch,
      onSettings: widget.onSettings,
      onSignOut: widget.onSignOut,
    ),
    body: AsyncView<List<CategoryNode>>(
      controller: _controller,
      onSignIn: widget.onSignIn,
      builder: (context, forest) {
        if (forest.isEmpty) return const _EmptyLibrary();
        final filtering = _filter.trim().isNotEmpty;
        final rows = visibleRows(
          forest,
          _expanded,
          filter: _filter,
          sort: _sort,
        );
        return Column(
          children: [
            _FilterBar(
              filter: _filter,
              sort: _sort,
              onFilter: (value) => setState(() => _filter = value),
              onSort: () => setState(() => _sort = _sort.next),
            ),
            Expanded(
              child: rows.isEmpty
                  ? const _NoMatch()
                  // ListView.builder over a FLATTENED list. A nested tree of
                  // Columns builds every descendant on every frame whether or
                  // not it is on screen, and a category list has no documented
                  // bound either (SPEC.md L2 — nothing here paginates).
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) => CategoryRow(
                        row: rows[index],
                        // A filtered list is flat, so it is not indented and
                        // nothing on it expands: every match is already
                        // showing, and a caret that revealed a child the
                        // filter had excluded would contradict the box above.
                        depth: filtering ? 0 : rows[index].node.depth,
                        onOpen: () => widget.onOpen(rows[index].node.category),
                        onToggle: filtering || !rows[index].expandable
                            ? null
                            : () => setState(() {
                                final id = rows[index].node.category.id;
                                if (!_expanded.remove(id)) _expanded.add(id);
                              }),
                      ),
                    ),
            ),
          ],
        );
      },
    ),
  );
}

/// The design's filter field and its sort toggle.
///
/// **The filter is local, and there is no other honest option.** Nothing on
/// this server paginates and there is no category search endpoint, so the whole
/// forest is already in memory; a round trip here would be a request for
/// something the client is holding.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.sort,
    required this.onFilter,
    required this.onSort,
  });

  final String filter;
  final CategorySort sort;
  final ValueChanged<String> onFilter;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              // 48, not the design's 36, for `androidTapTargetGuideline` —
              // see `CategoryRow`.
              height: 48,
              child: TextField(
                onChanged: onFilter,
                style: TextStyle(fontSize: 13, color: palette.text),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: palette.bar,
                  hintText: 'Filter categories',
                  hintStyle: TextStyle(fontSize: 13, color: palette.textDim),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 15,
                    color: palette.textDim,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 32),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.outline),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onSort,
            icon: const Icon(Icons.swap_vert, size: 14),
            label: Text(sort.label),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              foregroundColor: palette.accentBright,
              side: BorderSide(color: palette.accent),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A library with no categories at all.
///
/// An empty state, not a forever-spinner. A freshly installed server really
/// does have nothing in it, and a spinner would say "wait" about something
/// that is never going to arrive.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => const _Notice(
    'This server has no categories yet. Categories are the top-level '
    'folders in its media directory.',
  );
}

/// A filter that matched nothing — the user's own doing, not the server's.
class _NoMatch extends StatelessWidget {
  const _NoMatch();

  @override
  Widget build(BuildContext context) =>
      const _Notice('No category matches that.');
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: FileFinPalette.of(context).textMuted),
      ),
    ),
  );
}

/// One row of the tree, at the design's 46 points.
///
/// **A `Container` rather than a `ListTile`**, because a `ListTile` is 56 tall
/// before its own padding and cannot be told otherwise; the design's tree fits
/// ten rows on a phone by being short, and ten is the number that makes a
/// library scannable without scrolling.
///
/// **48 rather than the design's 46**, and the two points are not a rounding
/// error: `androidTapTargetGuideline` requires 48 and this suite runs it, so a
/// 46-point row is a row that fails the gate. The design was drawn in CSS
/// pixels against no such rule.
class CategoryRow extends StatelessWidget {
  /// Draws [row], indenting it by its depth.
  const CategoryRow({
    required this.row,
    required this.depth,
    required this.onOpen,
    this.onToggle,
    super.key,
  });

  /// The node and its expansion state.
  final VisibleRow row;

  /// How far to indent it. The node's own depth in the tree, and zero in a
  /// filtered list, which has no tree to be in.
  final int depth;

  /// Opens this category.
  final VoidCallback onOpen;

  /// Expands or collapses it, or null when it has no children — or when a
  /// filter is showing, where there is no hierarchy to open.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    final category = row.node.category;
    return InkWell(
      onTap: onOpen,
      child: Container(
        height: 48,
        padding: EdgeInsets.only(left: 12 + depth * 20, right: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: palette.hairline)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: onToggle == null
                  ? null
                  : IconButton(
                      onPressed: onToggle,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 14,
                      color: palette.textDim,
                      tooltip: row.expanded ? 'Collapse' : 'Expand',
                      icon: Icon(
                        row.expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.chevron_right,
                      ),
                    ),
            ),
            Icon(Icons.folder_outlined, size: 16, color: palette.textFaint),
            const SizedBox(width: 8),
            Expanded(
              // `leaf`, never `name`. `name` is the FULL PATH — a nested
              // category reads "Films/Documentaries" — which would print the
              // whole path on a row already sitting under its parent. Captured
              // at M3.2 against the real server rather than taken from the doc.
              child: Text(
                category.leaf,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: palette.text),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              counts(category),
              style: mono(size: 11, color: palette.textFaint),
            ),
          ],
        ),
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
  ///
  /// **Numerals only, in the mono face**, which is the design's own compression
  /// of the same line: the words "items" and "files" were the widest thing on
  /// a 46-point row and the two numbers carry all of it.
  @visibleForTesting
  static String counts(Category category) {
    if (category.media == 0 && category.files == 0) return '—';
    return '${category.media} · ${category.files}';
  }
}
