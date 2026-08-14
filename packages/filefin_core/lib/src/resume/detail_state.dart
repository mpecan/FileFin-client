import 'package:filefin_core/src/models/media_detail.dart';
import 'package:filefin_core/src/resume/engine.dart';
import 'package:filefin_core/src/resume/watch_state.dart';

/// Folds a [WatchState] back onto the detail payload it belongs to, so a
/// screen can show the result of a watch-state write without re-fetching.
///
/// This is F10's optimistic update (D17), which is exact rather than hopeful —
/// D17 carries the proof and the contrast with F9, which is not.
///
/// It folds through [deriveView] rather than copying [WatchState]'s fields
/// across, because [MediaDetail] carries the derived view rather than the
/// stored pointer (D15). Every `files[i].watched` moves with it, and an
/// out-of-range rating survives (D16).
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
