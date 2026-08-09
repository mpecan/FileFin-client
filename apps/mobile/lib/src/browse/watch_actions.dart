import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/foundation.dart';

/// F10's four writes on one screen: published immediately, serialised, and
/// reverted when the server refuses.
///
/// **Published before the round trip, always.** A toggle that waits for a
/// server to answer is unusable over cellular — the tap appears to do nothing
/// for a second and people press it again. So the screen is updated from
/// [applyWatchState] first and put back if the write fails, and the failure is
/// named rather than swallowed.
///
/// **That is only honest because the prediction is exact.** The four writes are
/// total assignments in the server's own fold, and `applyWatchState`'s comment
/// carries the proof and the contrast with F9's `applyProgress`, which has an
/// ambiguity class and therefore a refetch path. There is no refetch path here
/// and there does not need to be one.
///
/// **Exactly one write in flight, and a tap during it is refused visibly**
/// (G5). The alternative — a queue — was considered and rejected: with three
/// writes pending, "what does a failure revert to" has no answer a user could
/// predict, and that ambiguity is what would turn the optimistic value into a
/// lie. Refusing is worse UX and better behaviour.
///
/// It imports no widget, so every case below is a plain `test()` with no
/// binding and no pumping.
class WatchActions extends ChangeNotifier {
  /// Writes through [api] and hands each optimistic payload to [publish].
  WatchActions({
    required LibraryApi api,
    required void Function(MediaDetail) publish,
  }) : _api = api,
       _publish = publish;

  final LibraryApi _api;
  final void Function(MediaDetail) _publish;

  bool _busy = false;
  bool _wrote = false;
  String? _notice;

  /// Whether a write is in flight. Every control is disabled while it is.
  bool get busy => _busy;

  /// Whether any write has succeeded, which is what the home rows need to know.
  ///
  /// The rows come from the `user_state` mirror and are ordered by an `updated`
  /// stamp that **every** write re-stamps (M6.0/E-3), so a screen that changed
  /// anything has invalidated an ordering it cannot recompute. This is the flag
  /// the detail route pops with.
  bool get wrote => _wrote;

  /// What to tell the user right now, or null when there is nothing to say.
  String? get notice => _notice;

  /// `POST .../favorite`.
  Future<void> favourite(MediaDetail detail, {required bool favorite}) => _run(
    detail,
    setFavorite(WatchState.fromDetail(detail), favorite: favorite),
    () => _api.setFavorite(detail.id, favorite: favorite),
  );

  /// `POST .../rating` — 1-10, and 0 is how the server clears one.
  Future<void> rate(MediaDetail detail, {required int rating}) => _run(
    detail,
    setRating(WatchState.fromDetail(detail), rating: rating),
    () => _api.setRating(detail.id, rating: rating),
  );

  /// `POST .../watched` — sets or clears the flag and **keeps the pointer**.
  ///
  /// Pointing this at [LibraryApi.clearWatched] is the single most valuable
  /// mutation to try against this milestone's tests: the widget case that
  /// asserts *Continue 0:45* reappears, and `watch_state_test.dart`'s step 5
  /// against the real binary, both go red.
  Future<void> markWatched(MediaDetail detail, {required bool watched}) => _run(
    detail,
    setWatched(WatchState.fromDetail(detail), watched: watched),
    () => _api.setWatched(detail.id, watched: watched),
  );

  /// `DELETE .../watched` — clears the flag **and** the pointer.
  Future<void> clearWatchState(MediaDetail detail) => _run(
    detail,
    clearWatched(WatchState.fromDetail(detail)),
    () => _api.clearWatched(detail.id),
  );

  Future<void> _run(
    MediaDetail current,
    WatchState next,
    Future<void> Function() write,
  ) async {
    if (_busy) {
      _notice = 'Still saving the last change. Try again in a moment.';
      notifyListeners();
      return;
    }
    _busy = true;
    _notice = null;
    _publish(applyWatchState(current, next));
    notifyListeners();
    try {
      await write();
      _wrote = true;
    } on FileFinApiException catch (error) {
      // The revert is the whole contract of an optimistic update: the screen
      // said something happened, and it did not.
      _publish(current);
      final message = describeApiError(error);
      _notice = '${message.title}. ${message.detail}';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
