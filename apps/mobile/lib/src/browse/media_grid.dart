import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The poster grid itself, and the thing large libraries stress.
///
/// **One widget for the category listing and for search results**, which is
/// structural rather than tidy: a second copy would be that virtualisation
/// duplicated. That is what the `itemCount`, the
/// `addAutomaticKeepAlives: false` and the sort-free `build()` are for.
///
/// **It renders nothing for an empty list, deliberately.** What "empty" means
/// differs by caller — a category with nothing in it and a search with no
/// matches are different sentences, and the second has to quote the query —
/// so the wording belongs to the screen rather than to the grid.
class MediaGrid extends StatelessWidget {
  /// Draws [items] as posters fetched through [api]; [onOpen] opens one.
  const MediaGrid({
    required this.api,
    required this.items,
    required this.onOpen,
    super.key,
  });

  /// The port the posters come from.
  final LibraryApi api;

  /// What to draw, exactly as the caller loaded it.
  final List<MediaSummary> items;

  /// Opens one item's detail view.
  final void Function(MediaSummary item) onOpen;

  @override
  Widget build(BuildContext context) => GridView.builder(
    padding: const EdgeInsets.all(8),
    // A max EXTENT rather than a fixed cross-axis count: the tile stays a
    // readable size on a phone and on a tablet, instead of three enormous
    // tiles across on the second one.
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 160,
      childAspectRatio: 2 / 3.6,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    // Explicit, so the invariant the tests assert is a property of this file
    // rather than of whatever the framework defaults to today.
    scrollCacheExtent: const ScrollCacheExtent.pixels(400),
    addAutomaticKeepAlives: false,
    itemCount: items.length,
    itemBuilder: (context, index) =>
        PosterTile(api: api, item: items[index], onOpen: onOpen),
  );
}
