import 'dart:async';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/watch_actions.dart';
import 'package:flutter/material.dart';

/// Which un-watch a person picked. Two entries because they are two
/// operations, not one with a flag.
enum UnwatchChoice {
  /// `POST {"watched": false}` — the flag goes, the position stays.
  keepPosition,

  /// `DELETE .../watched` — the flag and the position both go.
  forgetEverything,
}

/// F10 on the detail screen: favourite, rating, and the two un-watches.
///
/// **The watched control is where this screen stops hiding the server's
/// asymmetry and starts explaining it.** `POST {"watched": false}` and
/// `DELETE .../watched` are different operations — measured against v0.20.3 at
/// M6.0/E-5, where the first returned the item to *continue* still 45 seconds
/// in and the second left it in no home row with the position gone — and no
/// wording that treats un-watching as one thing can be true of both. So an
/// unwatched item gets one button and a watched one gets a menu whose two
/// entries each say what happens to the position.
///
/// **Nothing is disabled while a write is in flight, deliberately.** A control
/// that greys out has no way to say why, and F10 allows exactly one write at a
/// time; so the controls stay tappable, a second tap is refused with a sentence
/// (G5), and the only thing `busy` draws is a progress bar saying a save is
/// under way.
class WatchStateControls extends StatelessWidget {
  /// Draws [detail]'s watch state and writes through [actions].
  const WatchStateControls({
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
      final notice = actions.notice;
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => unawaited(
                    actions.favourite(detail, favorite: !detail.favorite),
                  ),
                  tooltip: detail.favorite
                      ? 'Remove from favourites'
                      : 'Add to favourites',
                  icon: Icon(
                    detail.favorite ? Icons.favorite : Icons.favorite_border,
                  ),
                ),
                const SizedBox(width: 8),
                _WatchedControl(detail: detail, actions: actions),
              ],
            ),
            _Rating(detail: detail, actions: actions),
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
        ),
      );
    },
  );
}

class _WatchedControl extends StatelessWidget {
  const _WatchedControl({required this.detail, required this.actions});

  final MediaDetail detail;
  final WatchActions actions;

  @override
  Widget build(BuildContext context) {
    if (!detail.watched) {
      return FilledButton.tonalIcon(
        onPressed: () => unawaited(actions.markWatched(detail, watched: true)),
        icon: const Icon(Icons.check),
        label: const Text('Mark watched'),
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
      child: const Chip(
        avatar: Icon(Icons.check_circle, size: 18),
        label: Text('Watched'),
      ),
    );
  }
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
/// at M6.0/E-6, where a hand-edited `meta.json` served `rating: 99` — and a
/// `DropdownButton` whose `value` is not among its items asserts rather than
/// rendering. So an out-of-range rating is shown as itself, with no item
/// selected and a line saying what picking one will do.
class _Rating extends StatelessWidget {
  const _Rating({required this.detail, required this.actions});

  final MediaDetail detail;
  final WatchActions actions;

  @override
  Widget build(BuildContext context) {
    final rating = detail.rating;
    final inRange = rating >= 0 && rating <= 10;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Your rating'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: inRange ? rating : null,
                hint: Text('$rating'),
                onChanged: (value) {
                  if (value != null) {
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
      ),
    );
  }
}
