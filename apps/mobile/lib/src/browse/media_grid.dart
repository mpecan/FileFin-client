import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The poster grid itself, and NF2's subject.
///
/// **One widget for the category listing and for search results, and that is
/// the structural point.** Both draw the same `MediaSummary[]` the same way,
/// and a second copy would be NF2's virtualisation duplicated: `just dupes`
/// objects at 15 lines and 50 tokens, and long before that it is two places for
/// the delegate to drift apart. Extracting it also means the proofs below are
/// written once and inherited by both callers rather than owed twice.
///
/// **The whole array arrives at once** — nothing on this server paginates
/// (SPEC.md L2) — so the grid must be virtualised and the posters lazy. What
/// that means concretely, and what the tests assert:
///
/// - `GridView.builder` with an `itemCount`, so per-frame build and layout cost
///   O(visible) rather than O(everything). A `Column` or a `.map().toList()`
///   over the items would quietly make it O(everything) again.
/// - `addAutomaticKeepAlives: false`, so a tile scrolled away is really
///   disposed — which is what cancels its poster request. With keep-alives on,
///   every tile ever visited stays live and holds its bytes. **Stated as a
///   guard rather than as a tested invariant:** a keep-alive only exists once
///   a child mixes in `AutomaticKeepAliveClientMixin`, nothing under
///   `apps/mobile/lib` does, so flipping this flag today changes nothing a
///   rendering test can see. It is here for the tile that one day does, and the
///   flag itself is asserted on the delegate so it cannot be dropped silently.
/// - the item list is whatever the caller loaded. `build()` does no sorting,
///   filtering or copying, because all three are O(n) per frame.
///
/// **It renders nothing for an empty list, deliberately.** What "empty" means
/// differs by caller — a category with nothing in it and a search with no
/// matches are different sentences, and the second one has to quote the query —
/// so the wording belongs to the screen and not to the grid.
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
