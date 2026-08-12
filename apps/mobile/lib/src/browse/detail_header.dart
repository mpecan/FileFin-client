import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/poster_image_provider.dart';
import 'package:filefin_mobile/src/browse/watch_actions.dart';
import 'package:filefin_mobile/src/browse/watch_state_controls.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';

/// The design's 186-point title header: art, a gradient, and three controls.
///
/// **The art is the poster, because there is no backdrop.** The design draws a
/// wide `backdrop` behind the title; `GET /api/media/{id}/poster` is the only
/// image this server serves (`docs/server-api.md`), so the poster is used
/// cropped from the top and dimmed. When there is none — the ordinary case for
/// an un-enriched library — the header is the raised surface with no image at
/// all rather than a broken frame.
class DetailHeader extends StatelessWidget {
  /// Draws [detail] under [api]'s poster, writing favourites through
  /// [actions].
  const DetailHeader({
    required this.api,
    required this.detail,
    required this.actions,
    required this.posterToken,
    super.key,
  });

  /// Where the poster comes from.
  final LibraryApi api;

  /// The item.
  final MediaDetail detail;

  /// Where the heart writes to.
  final WatchActions actions;

  /// Cancelled when the screen closes, so a poster still in flight is dropped.
  final CancelToken posterToken;

  /// The design's header height.
  static const height = 186.0;

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: palette.raised),
          if (detail.hasPoster)
            Image(
              image: PosterImageProvider(
                api: api,
                media: detail.id,
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
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.18, 0.45, 1],
                colors: [
                  palette.background.withValues(alpha: 0.75),
                  palette.background.withValues(alpha: 0.55),
                  palette.background.withValues(alpha: 0.35),
                  palette.background,
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: 'Back',
                  color: palette.text,
                  icon: const Icon(Icons.arrow_back),
                ),
                const Spacer(),
                FavouriteButton(detail: detail, actions: actions),
                const SizedBox(width: 4),
              ],
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.title.isEmpty ? 'Untitled' : detail.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                    color: palette.text,
                  ),
                ),
                // Omitted entirely when every clause was a model default: an
                // un-enriched item with no year, no files and no genres has
                // nothing to say here, and an empty `Text` is a blank line
                // under the title rather than a fact.
                if (headerFacts(detail).isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    headerFacts(detail),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(size: 12, color: palette.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The mono line under the title: only what the payload actually carries.
///
/// **Every clause is omitted when its source is the model's default**, because
/// each default is "the server said nothing" rather than a value. A year of 0
/// is not the year zero, an item with no seasons is not "0 seasons", and a
/// library with no genres is the ordinary un-enriched case. The design's
/// example line — `1975 · 2 seasons · 12 files · comedy` — is what a fully
/// enriched show produces; a bare one produces just its file count.
///
/// Public only so a test can reach it; nothing outside this library calls it
/// (§5, `public_member_no_consumer`).
@visibleForTesting
String headerFacts(MediaDetail detail) {
  final seasons = detail.files
      .map((file) => file.season)
      .where((season) => season > 0)
      .toSet()
      .length;
  final files = detail.files.length;
  return [
    if (detail.year != 0) '${detail.year}',
    if (seasons == 1) '1 season' else if (seasons > 1) '$seasons seasons',
    if (files == 1) '1 file' else if (files > 1) '$files files',
    if (detail.genres.isNotEmpty) detail.genres.first.toLowerCase(),
  ].join(' · ');
}
