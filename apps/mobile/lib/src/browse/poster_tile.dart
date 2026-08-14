import 'package:dpad/dpad.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/poster_image_provider.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';

/// The two shapes a browsing tile comes in.
///
/// **The wide one is not a still, and the design assumed it was.** Every
/// `Continue` card in `FileFin Redesign.dc.html` carries a 16:9 frame, a
/// progress bar and an "N min left" pill. `GET /api/home` sends
/// `{id, title, year, hasPoster, watched}` and nothing else — no position, no
/// duration, no landscape artwork anywhere in the API — so the bar and the
/// pill would have to be invented, and the contract is observed. What
/// survives is the *rhythm* the design is built on: one wide row above two
/// narrow ones, so resume reads as the first thing on the screen. The frame is
/// filled with the poster, cropped from the top where the artwork lives.
enum MediaTileShape {
  /// A 2:3 poster — the library's own shape.
  poster(width: 82, imageHeight: 123, radius: 6),

  /// A wide card, for the row a user is meant to reach first.
  wide(width: 214, imageHeight: 120, radius: 8);

  const MediaTileShape({
    required this.width,
    required this.imageHeight,
    required this.radius,
  });

  /// How wide one tile is.
  final double width;

  /// How tall its artwork is.
  final double imageHeight;

  /// The corner radius of that artwork.
  final double radius;

  /// The height of a row of these, artwork and caption together.
  double get rowHeight => imageHeight + (this == poster ? 37 : 43);

  /// Which poster size to ask the server for.
  ///
  /// Private, because only this file asks: a wide card is a poster cropped, so
  /// it needs the larger fetch even though it is drawn shorter.
  PosterSize get _posterSize =>
      this == poster ? PosterSize.tile : PosterSize.detail;
}

/// One item in a poster grid or a home row.
///
/// **Stateful only to own a `CancelToken`.** A tile scrolled out of the
/// viewport is disposed, and disposing cancels — without that, flinging through
/// a 5000-item category queues every request it passed and the ones the user
/// actually stopped on wait behind them.
class PosterTile extends StatefulWidget {
  /// Draws [item] in [shape], fetching its poster through [api].
  const PosterTile({
    required this.api,
    required this.item,
    required this.onOpen,
    this.shape = MediaTileShape.poster,
    super.key,
  });

  /// The port the poster comes from.
  final LibraryApi api;

  /// The item this tile stands for.
  final MediaSummary item;

  /// Opens the detail view.
  final void Function(MediaSummary item) onOpen;

  /// Which of the two shapes to draw.
  final MediaTileShape shape;

  @override
  State<PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<PosterTile> {
  final _token = CancelToken();

  @override
  void dispose() {
    _token.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    final title = widget.item.title.isEmpty ? 'Untitled' : widget.item.title;
    // `MergeSemantics` OUTSIDE the focus node, not inside it: `DpadFocusable`
    // introduces a `Focus` of its own, and a merge below that leaves the
    // outermost tappable node — the one `labeledTapTargetGuideline` measures —
    // carrying the tap action and no name. Which is also what a screen reader
    // would then announce: "button".
    return MergeSemantics(
      child: DpadFocusable(
        onSelect: () => widget.onOpen(widget.item),
        child: InkWell(
          onTap: () => widget.onOpen(widget.item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // `Expanded`, not a fixed height: the same tile is drawn inside a
              // row that sizes itself from `shape.rowHeight` and inside a grid
              // cell whose height comes from the delegate. Pinning the artwork
              // would leave the grid's tiles floating above a gap.
              Expanded(child: _artwork(palette)),
              const SizedBox(height: 5),
              if (widget.shape == MediaTileShape.wide)
                ..._wideCaption(palette, title)
              else
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.25,
                    color: palette.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _wideCaption(FileFinPalette palette, String title) => [
    Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: palette.text,
      ),
    ),
    // A year of 0 is the model's default for a payload without one, not a film
    // from the year zero — so the line is omitted rather than printed as "0".
    if (widget.item.year != 0)
      Text(
        '${widget.item.year}',
        style: mono(size: 11, color: palette.textDim),
      ),
  ];

  Widget _artwork(FileFinPalette palette) => ClipRRect(
    borderRadius: BorderRadius.circular(widget.shape.radius),
    // A RepaintBoundary per poster: an image that finishes decoding repaints
    // its own layer instead of the whole scrolling viewport.
    child: RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.item.hasPoster)
            Image(
              image: PosterImageProvider(
                api: widget.api,
                media: widget.item.id,
                size: widget.shape._posterSize,
                cancelToken: _token,
              ),
              fit: BoxFit.cover,
              // Top-centre rather than centred, because the wide shape crops a
              // 2:3 poster to 16:9 and the artwork that identifies a title —
              // the face, the logo — is in its upper half.
              alignment: Alignment.topCenter,
              // `hasPoster` is the server's claim, and a claim can be wrong:
              // the file can be deleted between the listing and the fetch. The
              // placeholder is the same one the `false` branch draws, because
              // to a user the two are the same situation.
              errorBuilder: (context, _, _) => const PosterPlaceholder(),
              frameBuilder: (context, child, frame, wasSync) =>
                  posterStillLoading(frame, wasSync: wasSync)
                  ? const PosterPlaceholder()
                  : child,
            )
          else
            const PosterPlaceholder(),
          if (widget.item.watched)
            Positioned(
              top: 5,
              right: 5,
              child: Icon(
                Icons.check_circle,
                size: 14,
                color: palette.accentBright,
              ),
            ),
        ],
      ),
    ),
  );
}

/// Whether the poster has not arrived yet, given `Image`'s frame callback.
///
/// A named function rather than an inline condition, because it is the one
/// piece of logic in this file and inline it was untestable: reaching it needs
/// a real image decode, which is engine-side async that a `testWidgets` body's
/// `FakeAsync` clock does not drive. `just mutants` said so — both `frame ==
/// null || !wasSync` and `frame != null && !wasSync` survived the whole suite,
/// and each of them is a tile that shows a placeholder over a poster it has.
///
/// [wasSync] is true when the image was already in the `ImageCache` and was
/// available on the very first build. In that case there is nothing to wait
/// for even though [frame] is null on that first call.
@visibleForTesting
bool posterStillLoading(int? frame, {required bool wasSync}) =>
    frame == null && !wasSync;

/// What a tile shows when there is no poster — which is normal.
///
/// An un-enriched library has no artwork at all, and the server answers those
/// requests with a 404 that `docs/server-api.md` calls the ordinary case. A
/// broken-image glyph would report a fault where there is none.
///
/// **It does NOT repeat the title.** The first version drew the title here as
/// well as in the caption below, so every posterless tile said the same words
/// twice — a widget test looking for one of them found two, which is how this
/// was noticed. The caption is always there; this is the space where a poster
/// would have been.
class PosterPlaceholder extends StatelessWidget {
  /// Fills the space a poster would have occupied.
  const PosterPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    // The palette is read once into a local rather than twice inline, which is
    // also what stops `just mutants` reporting an unkillable survivor: its
    // argument-swap rule rewrote the one-argument `FileFinPalette.of(context)`
    // call to byte-identical text, so no assertion could ever tell the two
    // apart.
    final palette = FileFinPalette.of(context);
    return ColoredBox(
      color: palette.raised,
      child: Center(
        child: Icon(Icons.movie_outlined, color: palette.textFaint, size: 20),
      ),
    );
  }
}
