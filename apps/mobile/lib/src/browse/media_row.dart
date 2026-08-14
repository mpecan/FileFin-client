import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One labelled home row: a heading and a horizontal strip of tiles.
///
/// **It draws nothing at all when [items] is empty, and that is the row's own
/// decision rather than each caller's.** All three home buckets can be empty
/// independently — someone who has favourited nothing still has a *Continue*
/// row — and a heading over an empty strip reads as something missing rather
/// than something absent. One rule in one place, so the three call sites
/// cannot drift.
///
/// Virtualised for the reason `MediaGrid` is (D14): a heavy user's *Watched*
/// row is as long as their library.
class MediaRow extends StatelessWidget {
  /// Draws [items] under [label], fetching posters through [api].
  const MediaRow({
    required this.api,
    required this.label,
    required this.items,
    required this.onOpen,
    this.shape = MediaTileShape.poster,
    this.showCount = false,
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

  /// Which tile shape this row is built from.
  final MediaTileShape shape;

  /// Whether the heading carries the number of items to its right.
  ///
  /// The design shows it on *Continue* and nowhere else, and that asymmetry is
  /// the point: how many things are half-watched is a number people act on,
  /// how many they have ever favourited is not.
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final palette = FileFinPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                if (showCount) ...[
                  const Spacer(),
                  Text(
                    '${items.length}',
                    style: mono(size: 11, color: palette.textFaint),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: shape.rowHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              // Explicit for the reason `MediaGrid` gives: the invariant the
              // tests assert must be a property of this file rather than of
              // whatever the framework defaults to today.
              scrollCacheExtent: const ScrollCacheExtent.pixels(400),
              addAutomaticKeepAlives: false,
              itemCount: items.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: SizedBox(
                  width: shape.width,
                  child: PosterTile(
                    api: api,
                    item: items[index],
                    onOpen: onOpen,
                    shape: shape,
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
