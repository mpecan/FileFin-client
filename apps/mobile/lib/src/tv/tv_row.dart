import 'package:dpad/dpad.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The television's sizing of a browsing row.
///
/// Read off the design's `tv home` frame: a still card is 236 wide against the
/// phone's 214, a poster is 132 against 82, and the gutters go from 5 to 8.
/// Written as multipliers of [MediaTileShape] rather than as a second shape
/// enum, so the phone and the television cannot drift into different aspect
/// ratios.
extension _TvTileSize on MediaTileShape {
  /// How wide one tile is on a television.
  double get _tvWidth => this == MediaTileShape.poster ? 132 : 236;

  /// How tall a row of them is, artwork and caption together.
  double get _tvRowHeight =>
      _tvWidth / width * imageHeight +
      (this == MediaTileShape.poster ? 44 : 52);
}

/// One labelled row on a television, virtualised exactly as the phone's is.
///
/// **It draws nothing when [items] is empty**, which is the same rule
/// `MediaRow` states and for the same reason: all three home buckets can be
/// empty independently, and a heading over an empty strip reads as something
/// missing rather than something absent.
class TvRow extends StatelessWidget {
  /// Draws [items] under [label], fetching posters through [api].
  const TvRow({
    required this.api,
    required this.label,
    required this.items,
    required this.onOpen,
    this.shape = MediaTileShape.poster,
    super.key,
  });

  /// The port the posters come from.
  final LibraryApi api;

  /// The row's name.
  final String label;

  /// What to draw, exactly as the server ordered it.
  final List<MediaSummary> items;

  /// Opens one item's detail view.
  final void Function(MediaSummary item) onOpen;

  /// Which tile shape this row is built from.
  final MediaTileShape shape;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final palette = FileFinPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: palette.text,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: shape._tvRowHeight,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 36),
              // Explicit for the reason `MediaGrid` gives: the invariant the
              // tests assert must be a property of this file rather than of
              // whatever the framework defaults to today.
              scrollCacheExtent: const ScrollCacheExtent.pixels(600),
              addAutomaticKeepAlives: false,
              itemCount: items.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: shape._tvWidth,
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

/// A focus ring in the design's own violet, wrapped around anything.
///
/// **One widget rather than a `DpadFocusable` per call site**, because the ring
/// is the only thing a television user can use to tell where they are: the
/// design draws the identical `0 0 0 2px #968ae0` glow on a poster, a category
/// row, a keyboard key and a button, and four hand-rolled copies of it is four
/// chances for one of them to be subtly different.
class TvFocusable extends StatefulWidget {
  /// Wraps [child]; a select press calls [onSelect].
  const TvFocusable({required this.child, required this.onSelect, super.key});

  /// What the ring goes around.
  final Widget child;

  /// What a press of the remote's centre key does.
  final VoidCallback onSelect;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return DpadFocusable(
      onSelect: widget.onSelect,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: _focused
              ? [
                  BoxShadow(color: palette.accent, spreadRadius: 2),
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.5),
                    blurRadius: 26,
                  ),
                ]
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
