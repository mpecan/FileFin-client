import 'package:filefin_core/src/models/media_detail.dart';
import 'package:filefin_core/src/resume/engine.dart';
import 'package:filefin_core/src/resume/watch_state.dart';

/// Folds a [WatchState] back onto the detail payload it belongs to, so a
/// screen can show the result of a watch-state write without re-fetching.
///
/// **F10's optimistic update is exact, and that is a proof rather than a
/// hope.** The four writes it follows — `setWatched`, [clearWatched],
/// `setFavorite`, `setRating` — are *total assignments* in the server's own
/// fold (`media.go:406/434/472/489`): each one writes the field it names and
/// copies the rest through. `filefin_core`'s four mutators are those same
/// assignments, so the state handed here is the state the server now holds.
///
/// **The difference from F9 is what makes that safe to say.** `applyProgress`
/// has an ambiguity class — `WatchState.fromDetail` has to guess whether a
/// wire `(0, 0)` means a fresh pointer or an absent one, and a crossing report
/// on a single-file item is where the guess can be wrong, which is why
/// `PlaybackOutcome.needsDetailRefetch` exists. None of these four reads a
/// pointer, infers one, or depends on how `(0, 0)` was read: `setWatched`
/// keeps whatever pointer it was given and [clearWatched] drops it outright.
/// So F10 needs **no divergence-refetch path**, and no second
/// `PlaybackOutcome`.
///
/// [MediaDetail] carries the **derived view** rather than the stored pointer,
/// so the fold goes through [deriveView] rather than copying [WatchState]'s
/// fields across. That is what makes a pointer past the end of the file list
/// land as `0`/`0` here exactly as the server would report it.
///
/// **Every `files[i].watched` moves too**, and that half is a fix rather than
/// an addition: `media_detail_page.dart` folded four fields and left the file
/// rows carrying whatever the last fetch said. Invisible while nothing drew
/// them, and wrong the moment anything did.
///
/// **An out-of-range rating survives this fold, and that took a fix rather than
/// a rule about when to call it.** The doc here used to say the fold is applied
/// only after a real mutation, so a server-reported `rating: 99` (M6.0/E-6, and
/// the server does not clamp on read) could never be turned into "unrated" by
/// it. That was the wrong ground: `setFavorite`, `setWatched` and
/// `clearWatched` all round-trip through [WatchState.fromDetail], which
/// normalised the rating
/// away, so *a real mutation of favourite* dragged the clamped rating along
/// with it and wiped the 99 off the screen (M6.R/P1.4). `fromDetail` now copies
/// the rating through exactly as the server reports it, and its doc comment
/// carries the reasoning.
MediaDetail applyWatchState(MediaDetail detail, WatchState state) {
  final view = deriveView(state, fileCount: detail.files.length);
  return detail.copyWith(
    watched: view.watched,
    favorite: state.favorite,
    rating: state.rating,
    continueIndex: view.continueIndex.value,
    continueSeconds: view.continueSeconds,
    files: [
      for (var i = 0; i < detail.files.length; i++)
        detail.files[i].copyWith(watched: view.perFile[i]),
    ],
  );
}
