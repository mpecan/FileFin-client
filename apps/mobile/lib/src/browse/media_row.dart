import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One labelled home row: a heading and a horizontal strip of posters.
///
/// **It draws nothing at all when [items] is empty, and that is the row's own
/// decision rather than each caller's.** All three home buckets can be empty
/// independently — a user who has favourited nothing still has a *Continue
/// watching* row — and a heading over an empty strip reads as something
/// missing rather than something absent. One rule in one place, so the three
/// call sites cannot drift.
///
/// **Virtualised for the same reason `MediaGrid` is** (SPEC.md L2 — nothing on
/// this server paginates): `/api/home` returns whole buckets, and
/// `homeBucket` (`db/home.go`) applies no limit, so a heavy user's *Watched*
/// row is as long as their library. A `Row` of `.map()`ed children would build
/// every one of them on every frame.
class MediaRow extends StatelessWidget {
  /// Draws [items] under [label], fetching posters through [api].
  const MediaRow({
    required this.api,
    required this.label,
    required this.items,
    required this.onOpen,
    super.key,
  });

  /// The port the posters come from.
  final LibraryApi api;

  /// The heading — the row's name, not the server's bucket key.
  final String label;

  /// What to draw, exactly as the server ordered it.
  ///
  /// **Never re-sorted here.** Every bucket arrives `ORDER BY us.updated DESC`
  /// and `updated` is re-stamped by *every* write, including a rating
  /// (M6.0/E-3), so the server's order carries information no client can
  /// reconstruct.
  final List<MediaSummary> items;

  /// Opens one item's detail view.
  final void Function(MediaSummary item) onOpen;

  /// How tall one strip is: a 2:3 poster at [_tileWidth] plus its caption.
  static const _rowHeight = 226.0;

  /// Narrower than the grid's 160, because a row is scanned rather than
  /// browsed and more of it should be visible at once.
  static const _tileWidth = 116.0;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _rowHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              // Explicit for the reason `MediaGrid` gives: the invariant the
              // tests assert must be a property of this file rather than of
              // whatever the framework defaults to today.
              scrollCacheExtent: const ScrollCacheExtent.pixels(400),
              addAutomaticKeepAlives: false,
              itemCount: items.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: _tileWidth,
                  child: PosterTile(
                    api: api,
                    item: items[index],
                    onOpen: onOpen,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
