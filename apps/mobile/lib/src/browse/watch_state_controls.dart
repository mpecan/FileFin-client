import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/watch_actions.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:flutter/material.dart';

/// Which un-watch a person picked. Two entries because they are two
/// operations, not one with a flag.
enum UnwatchChoice {
  /// `POST {"watched": false}` — the flag goes, the position stays.
  keepPosition,

  /// `DELETE.../watched` — the flag and the position both go.
  forgetEverything,
}

/// The watch-state controls, as four pieces the redesign places separately.
///
/// **The watched control is where this screen stops hiding the server's
/// asymmetry and starts explaining it**: un-watching is two different
/// operations (`docs/field-notes.md`), and no single wording is true of both.
/// So an unwatched item gets one button and a watched one gets a menu whose
/// two entries each say what happens to the position.
///
/// **Nothing is disabled while a write is in flight**: a control that
/// greys out has no way to say why, so they stay tappable, a second tap is
/// refused with a sentence, and `busy` draws only a progress bar. One class
/// became four at the redesign; the behaviour of each is unchanged.
class FavouriteButton extends StatelessWidget {
  /// Toggles [detail]'s favourite flag through [actions].
  const FavouriteButton({
    required this.detail,
    required this.actions,
    super.key,
  });

  /// The item, as the screen currently believes it to be.
  final MediaDetail detail;

  /// Where a tap goes.
  final WatchActions actions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: actions,
    builder: (context, _) => IconButton(
      onPressed: () =>
          unawaited(actions.favourite(detail, favorite: !detail.favorite)),
      tooltip: detail.favorite ? 'Remove from favourites' : 'Add to favourites',
      icon: Icon(
        detail.favorite ? Icons.favorite : Icons.favorite_border,
        color: detail.favorite ? FileFinPalette.of(context).accentBright : null,
      ),
    ),
  );
}

/// The check in the action row: mark watched, or the two ways back.
class WatchedButton extends StatelessWidget {
  /// Draws [detail]'s watched state and writes through [actions].
  const WatchedButton({
    required this.detail,
    required this.actions,
    super.key,
  });

  /// The item, as the screen currently believes it to be.
  final MediaDetail detail;

  /// Where a tap goes.
  final WatchActions actions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: actions,
    builder: (context, _) {
      final palette = FileFinPalette.of(context);
      if (!detail.watched) {
        return _SquareButton(
          tooltip: 'Mark watched',
          palette: palette,
          onPressed: () =>
              unawaited(actions.markWatched(detail, watched: true)),
          child: const Icon(Icons.check, size: 18),
        );
      }
      return PopupMenuButton<UnwatchChoice>(
        tooltip: 'Change watch state',
        onSelected: (choice) => unawaited(switch (choice) {
          UnwatchChoice.keepPosition => actions.markWatched(
            detail,
            watched: false,
          ),
          UnwatchChoice.forgetEverything => actions.clearWatchState(detail),
        }),
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: UnwatchChoice.keepPosition,
            child: _Consequence(
              title: 'Mark as unwatched',
              detail:
                  'Keeps where you left off, so it goes back to Continue '
                  'watching.',
            ),
          ),
          PopupMenuItem(
            value: UnwatchChoice.forgetEverything,
            child: _Consequence(
              title: 'Clear watch state',
              detail: 'Forgets the position too, so it leaves every list.',
            ),
          ),
        ],
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accentFill,
            border: Border.all(color: palette.accent),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.check_circle,
            size: 18,
            color: palette.accentSoft,
            semanticLabel: 'Watched',
          ),
        ),
      );
    },
  );
}

/// A 44-point outlined square — the design's secondary action shape.
class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.tooltip,
    required this.palette,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final FileFinPalette palette;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        fixedSize: const Size.square(44),
        minimumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        foregroundColor: palette.textMuted,
        side: BorderSide(color: palette.outline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: child,
    ),
  );
}

/// What a write that failed has to say, and whether one is in flight.
///
/// Drawn once, under the action row, rather than beside each control: the
/// writes allows exactly one write at a time, so there is only ever one thing
/// to say.
class WatchStateNotice extends StatelessWidget {
  /// Reports on [actions].
  const WatchStateNotice({required this.actions, super.key});

  /// The writer being watched.
  final WatchActions actions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: actions,
    builder: (context, _) {
      final notice = actions.notice;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (actions.busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                notice,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}

/// One menu entry: what it does, and what that costs.
class _Consequence extends StatelessWidget {
  const _Consequence({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(title),
      Text(detail, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

/// The rating, as whole numbers with an explicit way back to "not rated".
///
/// **A value outside 0-10 is reachable and this branch is correctness, not
/// polish.** The server validates a rating on write and not on read — measured
/// at, where a hand-edited `meta.json` served `rating: 99` — and a
/// `DropdownButton` whose `value` is not among its items asserts rather than
/// rendering. So an out-of-range rating is shown as itself, with no item
/// selected and a line saying what picking one will do.
class RatingField extends StatelessWidget {
  /// Draws [detail]'s rating and writes through [actions].
  const RatingField({required this.detail, required this.actions, super.key});

  /// The item, as the screen currently believes it to be.
  final MediaDetail detail;

  /// Where a choice goes.
  final WatchActions actions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: actions,
    builder: (context, _) {
      final rating = detail.rating;
      final inRange = rating >= 0 && rating <= 10;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Your rating'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: inRange ? rating : null,
                hint: Text('$rating'),
                // `value != rating` as well as non-null: a `DropdownButton`
                // calls this for the entry that is already selected, and every
                // write re-stamps `updated`, which is the ordering key of all
                // three home rows. So re-picking the 7 an item
                // already has would shuffle somebody's *Continue watching* for
                // nothing. `rating` rather than `detail.rating` is deliberate:
                // an out-of-range value is not selected, so every entry
                // differs from it and all eleven stay pickable.
                onChanged: (value) {
                  if (value != null && value != rating) {
                    unawaited(actions.rate(detail, rating: value));
                  }
                },
                items: [
                  for (var value = 0; value <= 10; value++)
                    DropdownMenuItem(
                      value: value,
                      child: Text(value == 0 ? 'Not rated' : '$value'),
                    ),
                ],
              ),
            ],
          ),
          if (!inRange)
            Text(
              'This server reports $rating, which is outside 1-10. Choosing a '
              'rating above replaces it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      );
    },
  );
}
