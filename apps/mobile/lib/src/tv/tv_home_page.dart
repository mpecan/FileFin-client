import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/poster_image_provider.dart';
import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:filefin_mobile/src/tv/tv_row.dart';
import 'package:flutter/material.dart';

/// F6 on a television: a hero over the same three rows.
///
/// **The hero is the first item of the *continue* bucket, and it is the whole
/// argument for the screen.** That bucket arrives `ORDER BY us.updated DESC`
/// (M6.0/E-3), so its first entry is the last thing this person watched — which
/// is what a television is switched on to carry on with.
class TvHomePage extends StatefulWidget {
  /// Shows [api]'s home rows; [onOpen] opens an item.
  const TvHomePage({
    required this.api,
    required this.onOpen,
    this.onSignIn,
    super.key,
  });

  /// Where the rows and the posters come from.
  final LibraryApi api;

  /// Opens one item's detail view.
  final void Function(MediaSummary item) onOpen;

  /// Where a `SessionExpired` sends the user (F3's last resort).
  final VoidCallback? onSignIn;

  @override
  State<TvHomePage> createState() => TvHomePageState();
}

/// The state, public for one reason: [reload].
class TvHomePageState extends State<TvHomePage> {
  late final AsyncController<HomeRows> _controller = AsyncController<HomeRows>(
    (token) => widget.api.home(cancelToken: token),
  );

  final _heroToken = CancelToken();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _heroToken.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Refetches all three rows, after a write on the detail screen.
  Future<void> reload() => _controller.load();

  @override
  Widget build(BuildContext context) => AsyncView<HomeRows>(
    controller: _controller,
    onSignIn: widget.onSignIn,
    builder: (context, rows) {
      final hero = rows.continueRow.firstOrNull ?? rows.favorites.firstOrNull;
      if (hero == null && rows.completed.isEmpty) return const _NothingYet();
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hero != null)
              TvHero(
                api: widget.api,
                item: hero,
                resuming: rows.continueRow.isNotEmpty,
                posterToken: _heroToken,
                onOpen: () => widget.onOpen(hero),
              ),
            TvRow(
              api: widget.api,
              label: 'Continue',
              items: rows.continueRow,
              onOpen: widget.onOpen,
              shape: MediaTileShape.wide,
            ),
            TvRow(
              api: widget.api,
              label: 'Favourites',
              items: rows.favorites,
              onOpen: widget.onOpen,
            ),
            TvRow(
              api: widget.api,
              label: 'Watched',
              items: rows.completed,
              onOpen: widget.onOpen,
            ),
            const SizedBox(height: 32),
          ],
        ),
      );
    },
  );
}

/// The 330-point banner at the top of the television's home screen.
class TvHero extends StatelessWidget {
  /// Draws [item] as the thing to carry on with.
  const TvHero({
    required this.api,
    required this.item,
    required this.resuming,
    required this.posterToken,
    required this.onOpen,
    super.key,
  });

  /// Where the artwork comes from.
  final LibraryApi api;

  /// What the hero is about.
  final MediaSummary item;

  /// Whether this came from the *continue* bucket rather than *favourites*.
  ///
  /// It changes the eyebrow and nothing else, because it changes what is true:
  /// an item nobody has started is not something to continue watching.
  final bool resuming;

  /// Cancelled when the screen closes.
  final CancelToken posterToken;

  /// Opens the item's detail screen, where resuming actually happens.
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return SizedBox(
      height: 330,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.hasPoster)
            Image(
              image: PosterImageProvider(
                api: api,
                media: item.id,
                size: PosterSize.detail,
                cancelToken: posterToken,
              ),
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (context, _, _) => const SizedBox.shrink(),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                stops: const [0, 0.34, 0.62, 1],
                colors: [
                  palette.background,
                  palette.background,
                  palette.background.withValues(alpha: 0.4),
                  palette.background.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: const [0, 0.46],
                colors: [
                  palette.background,
                  palette.background.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(44, 56, 44, 24),
            child: SizedBox(
              width: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resuming ? 'CONTINUE WATCHING' : 'FROM YOUR FAVOURITES',
                    style: eyebrow(size: 12, color: palette.accentBright),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title.isEmpty ? 'Untitled' : item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 44,
                      height: 1.05,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.4,
                      color: palette.text,
                    ),
                  ),
                  if (item.year != 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${item.year}',
                      style: mono(size: 16, color: palette.textMuted),
                    ),
                  ],
                  const SizedBox(height: 18),
                  TvHeroButton(
                    // "Open", not "Resume", and the difference is honest: the
                    // position a resume needs lives on the item's DETAIL
                    // (`continueIndex`/`continueSeconds`) and the home payload
                    // carries neither, so a Resume here would either guess or
                    // cost a second request before the screen could draw.
                    label: 'Open',
                    palette: palette,
                    onPressed: onOpen,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hero's own call to action, at the size a sofa needs.
class TvHeroButton extends StatelessWidget {
  /// Draws [label] as the primary action.
  const TvHeroButton({
    required this.label,
    required this.palette,
    required this.onPressed,
    super.key,
  });

  /// The words on it.
  final String label;

  /// The ramp in force.
  final FileFinPalette palette;

  /// What a press does.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TvFocusable(
    onSelect: onPressed,
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.play_arrow, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: palette.accentFill,
        foregroundColor: const Color(0xFFF5F4FF),
        side: BorderSide(color: palette.accentBright),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

/// Three empty rows, which is what a fresh account really looks like.
class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(56),
        child: Text(
          'Nothing here yet. What you play, favourite or mark watched shows '
          'up on this screen. Open Library to get started.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, color: palette.textMuted),
        ),
      ),
    );
  }
}
