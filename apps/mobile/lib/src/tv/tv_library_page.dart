import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/media_grid.dart';
import 'package:filefin_mobile/src/browse/visible_rows.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:filefin_mobile/src/tv/tv_row.dart';
import 'package:flutter/material.dart';

/// F4 on a television: the tree on the left, the focused category's grid on
/// the right.
///
/// **Two panes rather than the phone's two screens**, and that is the design's
/// answer to a D-pad: a remote makes every push-and-return expensive, so
/// choosing a category has to change what is beside it rather than replace it.
/// A category's items are fetched when it is chosen, never before — the whole
/// library is not requested to draw a tree.
class TvLibraryPage extends StatefulWidget {
  /// Browses [api]; [onOpen] opens an item.
  const TvLibraryPage({
    required this.api,
    required this.onOpen,
    this.onSignIn,
    super.key,
  });

  /// Where the categories and the items come from.
  final LibraryApi api;

  /// Opens one item's detail view.
  final void Function(MediaSummary item) onOpen;

  /// Where a `SessionExpired` sends the user (F3's last resort).
  final VoidCallback? onSignIn;

  @override
  State<TvLibraryPage> createState() => _TvLibraryPageState();
}

class _TvLibraryPageState extends State<TvLibraryPage> {
  late final AsyncController<List<CategoryNode>> _tree =
      AsyncController<List<CategoryNode>>(
        (token) async =>
            buildCategoryTree(await widget.api.categories(cancelToken: token)),
      );

  AsyncController<List<MediaSummary>>? _items;
  final _expanded = <CategoryId>{};
  Category? _chosen;

  @override
  void initState() {
    super.initState();
    unawaited(_tree.load());
  }

  @override
  void dispose() {
    _items?.dispose();
    _tree.dispose();
    super.dispose();
  }

  void _choose(Category category) {
    if (_chosen?.id == category.id) return;
    final replacement = AsyncController<List<MediaSummary>>(
      (token) => widget.api.categoryMedia(category.id, cancelToken: token),
    );
    setState(() {
      // Disposed before the field is replaced, so the previous category's
      // request is cancelled rather than left racing the new one onto a grid
      // that has moved on.
      _items?.dispose();
      _items = replacement;
      _chosen = category;
    });
    unawaited(replacement.load());
  }

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return AsyncView<List<CategoryNode>>(
      controller: _tree,
      onSignIn: widget.onSignIn,
      builder: (context, forest) {
        if (forest.isEmpty) return const _EmptyLibrary();
        final rows = visibleRows(forest, _expanded);
        return Row(
          children: [
            SizedBox(
              width: 392,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: palette.hairline)),
                ),
                child: _Tree(
                  rows: rows,
                  chosen: _chosen,
                  palette: palette,
                  onChoose: _choose,
                  onToggle: (id) => setState(() {
                    if (!_expanded.remove(id)) _expanded.add(id);
                  }),
                ),
              ),
            ),
            Expanded(child: _grid(palette)),
          ],
        );
      },
    );
  }

  Widget _grid(FileFinPalette palette) {
    final items = _items;
    final chosen = _chosen;
    if (items == null || chosen == null) {
      return _Notice('Choose a category on the left.', palette: palette);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 34, 44, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                chosen.leaf,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: palette.text,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                categoryCounts(chosen),
                style: mono(size: 13, color: palette.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: AsyncView<List<MediaSummary>>(
              controller: items,
              onSignIn: widget.onSignIn,
              builder: (context, media) => media.isEmpty
                  ? _Notice('Nothing in this category.', palette: palette)
                  : MediaGrid(
                      api: widget.api,
                      items: media,
                      onOpen: widget.onOpen,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The counts beside a category's name, worded so 0 does not read as "empty".
///
/// `library.go:73-81` returns `media` and `files` as **0 when the cache is
/// unavailable**, exactly as it does for a genuinely empty category, so a
/// heading that said "0 items" would state as a fact something it does not
/// know.
///
/// Public only so a test can reach it; nothing outside this library calls it
/// (§5, `public_member_no_consumer`).
@visibleForTesting
String categoryCounts(Category category) {
  if (category.media == 0 && category.files == 0) return 'No items listed';
  return '${category.media} items · ${category.files} files';
}

class _Tree extends StatelessWidget {
  const _Tree({
    required this.rows,
    required this.chosen,
    required this.palette,
    required this.onChoose,
    required this.onToggle,
  });

  final List<VisibleRow> rows;
  final Category? chosen;
  final FileFinPalette palette;
  final void Function(Category) onChoose;
  final void Function(CategoryId) onToggle;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(28, 34, 20, 24),
    itemCount: rows.length,
    itemBuilder: (context, index) {
      final row = rows[index];
      final category = row.node.category;
      final selected = chosen?.id == category.id;
      return TvFocusable(
        onSelect: () => onChoose(category),
        child: InkWell(
          onTap: () => onChoose(category),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 56,
            margin: EdgeInsets.only(left: row.node.depth * 16.0, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? palette.accentFill : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 20,
                  color: palette.textDim,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.leaf,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          color: selected
                              ? const Color(0xFFF5F4FF)
                              : palette.textMuted,
                        ),
                      ),
                      Text(
                        categoryCounts(category),
                        style: mono(size: 12, color: palette.textFaint),
                      ),
                    ],
                  ),
                ),
                if (row.expandable)
                  IconButton(
                    onPressed: () => onToggle(category.id),
                    iconSize: 16,
                    color: palette.outlineStrong,
                    tooltip: row.expanded ? 'Collapse' : 'Expand',
                    icon: Icon(
                      row.expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => _Notice(
    'This server has no categories yet. Categories are the top-level folders '
    'in its media directory.',
    palette: FileFinPalette.of(context),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {required this.palette});

  final String text;
  final FileFinPalette palette;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(44),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, color: palette.textMuted),
      ),
    ),
  );
}
