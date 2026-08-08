import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/poster_image_provider.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';

/// One item in the poster grid.
///
/// **Stateful only to own a `CancelToken`.** A tile scrolled out of the
/// viewport is disposed, and disposing cancels — without that, flinging through
/// a 5000-item category queues every request it passed and the ones the user
/// actually stopped on wait behind them.
class PosterTile extends StatefulWidget {
  /// Draws [item], fetching its poster through [api].
  const PosterTile({
    required this.api,
    required this.item,
    required this.onOpen,
    super.key,
  });

  /// The port the poster comes from.
  final LibraryApi api;

  /// The item this tile stands for.
  final MediaSummary item;

  /// Opens the detail view.
  final void Function(MediaSummary item) onOpen;

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
  Widget build(BuildContext context) => InkWell(
    onTap: () => widget.onOpen(widget.item),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          // A RepaintBoundary per poster: an image that finishes decoding
          // repaints its own layer instead of the whole scrolling viewport.
          child: RepaintBoundary(
            child: widget.item.hasPoster
                ? Image(
                    image: PosterImageProvider(
                      api: widget.api,
                      media: widget.item.id,
                      size: PosterSize.tile,
                      cancelToken: _token,
                    ),
                    fit: BoxFit.cover,
                    // `hasPoster` is the server's claim, and a claim can be
                    // wrong — the poster file can be deleted between the
                    // listing and the fetch. The placeholder is the same one
                    // the `false` branch draws, because to a user the two are
                    // the same situation.
                    errorBuilder: (context, _, _) =>
                        const _NoPosterPlaceholder(),
                    frameBuilder: (context, child, frame, wasSync) =>
                        posterStillLoading(frame, wasSync: wasSync)
                        ? const _NoPosterPlaceholder()
                        : child,
                  )
                : const _NoPosterPlaceholder(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            widget.item.title.isEmpty ? 'Untitled' : widget.item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
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
class _NoPosterPlaceholder extends StatelessWidget {
  const _NoPosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    // The scheme is read once into a local rather than twice inline, which is
    // also what stops `just mutants` reporting an unkillable survivor: its
    // argument-swap rule rewrote the one-argument `Theme.of(context)` call to
    // byte-identical text, so no assertion could ever tell the two apart.
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.movie_outlined, color: scheme.outline),
      ),
    );
  }
}
