import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/resume/watch_state.dart';
import 'package:meta/meta.dart';

/// The fraction of a file that must be played for it to count as watched —
/// upstream's `WatchedThreshold` (`state/engine.go:7`).
///
/// The comparison is `>=`, so exactly 0.90 crosses.
const watchedThreshold = 0.90;

/// Resolves a pointer to an index into a file list of [fileCount] files, or -1.
///
/// This is the index-space `indexOf` (`state/engine.go:34-41`), and it is the
/// single place the "stale pointer" rule lives. Upstream answers -1 for a ref
/// that is not in `refs`; here that is an index outside the list, which is what
/// a file list that shrank or was renumbered between sessions leaves behind.
///
/// Both `applyProgress` and `deriveView` resolve ONCE through this and then
/// read
/// the resolved index, never the pointer's own. Reading the pointer directly is
/// the bug the captured vectors exist to catch: `continueSeconds =
/// pointer?.seconds ?? 0` reports a stale pointer's seconds where the server
/// reports 0.
/// Public only so a test can reach it; nothing outside this library calls
/// it (§5, `public_member_no_consumer`).
@visibleForTesting
int resolveIndex(ResumePointer? pointer, int fileCount) {
  if (pointer == null) return -1;
  final index = pointer.file.value;
  if (index < 0 || index >= fileCount) return -1;
  return index;
}

/// Go's `round` (`state/engine.go:43-48`): `int(x + 0.5)`, clamped at 0.
///
/// **Public because the progress policy has to dedupe in exactly this
/// arithmetic.** `decideReport` compares a new position against the seconds the
/// server stored for the last one; comparing raw doubles instead would drift
/// from the pointer by up to half a second per report, and `round(29.5) == 30`
/// versus `29.5 < 30` is the boundary where the two disagree. One rounding, one
/// place.
///
/// **Not Dart's `.round()`.** The two differ for negatives — `(-0.5).round()`
/// is -1 — and -0.5 is reachable from a seek to the very start of a file.
///
/// The non-finite guard is client hardening with no upstream counterpart:
/// Dart's
/// `.toInt()` throws on NaN and Infinity where Go's `int()` does not — and what
/// Go produces instead is worth naming, because only one of the three is a
/// deliberate difference. Measured on darwin/arm64 against upstream's own
/// `round`: `+Inf` → `9223372036854775807`, `NaN` → `0`, `-Inf` → `0` (through
/// the negative clamp). So returning 0 for `NaN` and `-Inf` agrees with Go by
/// accident of the platform, and `+Infinity` is the sole place we deliberately
/// answer something else. Neither is reachable over the wire: Go's
/// `encoding/json` refuses to marshal a non-finite float, so no server payload
/// can carry one. This is a decision about our runtime, not a claim about the
/// server.
int roundReportedSeconds(double x) {
  if (!x.isFinite) return 0;
  if (x < 0) return 0;
  return (x + 0.5).toInt();
}

/// Folds one playback report into [state] — upstream's `Apply`,
/// `state/engine.go:56-85`.
///
/// [fileCount] is the length of the item's file list, which is what the server
/// calls `refs`. The rules, in the order they apply:
///
/// 1. an out-of-range file index returns [state] **entirely unchanged**,
///    `watched` included. (The HTTP handler answers `400` instead and never
/// reaches the engine; `filefin_core` mirrors the engine, because that is the
///    function an optimistic UI has to reproduce.)
/// 2. `crossed` needs `duration > 0`, so a zero or negative duration never
///    crosses whatever the position.
/// 3. crossing a non-last file aims at the next file at 0 seconds; crossing the
///    last file sets `watched` and stays put.
/// 4. the pointer only ever moves forward, and the equal-index case
/// additionally
///    requires `!crossed` — which is where the last-file asymmetry comes from.
WatchState applyProgress(
  WatchState state,
  ProgressReport report, {
  required int fileCount,
}) {
  final file = report.file.value;
  if (file < 0 || file >= fileCount) return state;

  final last = fileCount - 1;
  final crossed =
      report.duration > 0 &&
      report.position / report.duration >= watchedThreshold;

  var targetIndex = file;
  var targetSeconds = roundReportedSeconds(report.position);
  var watched = state.watched;
  if (crossed) {
    if (file == last) {
      watched = true;
    } else {
      targetIndex = file + 1;
      targetSeconds = 0;
    }
  }

  final currentIndex = resolveIndex(state.pointer, fileCount);
  final advanced =
      targetIndex > currentIndex ||
      (targetIndex == currentIndex &&
          !crossed &&
          targetSeconds > state.pointer!.seconds);

  return state.copyWith(
    watched: watched,
    pointer: advanced
        ? ResumePointer(file: FileIndex(targetIndex), seconds: targetSeconds)
        : state.pointer,
  );
}

/// Derives what a detail view renders — upstream's `View`,
/// `state/engine.go:98-112`.
///
/// The pointer is resolved once and every row reads the resolved index. A
/// pointer that does not resolve therefore reads **identically to no pointer**:
/// index 0, 0 seconds, and no file marked watched — even though the pointer is
/// non-null and carries real seconds.
///
/// The file **at** the pointer is not marked watched; you are in the middle of
/// it. When the folder flag is set every file reads watched regardless.
WatchView deriveView(WatchState state, {required int fileCount}) {
  final pointerIndex = resolveIndex(state.pointer, fileCount);
  final resolved = pointerIndex >= 0;
  return WatchView(
    watched: state.watched,
    continueIndex: FileIndex(resolved ? pointerIndex : 0),
    continueSeconds: resolved ? state.pointer!.seconds : 0,
    perFile: [
      for (var i = 0; i < fileCount; i++) state.watched || i < pointerIndex,
    ],
  );
}

/// `POST /api/media/{id}/watched` — sets or clears the flag and **keeps the
/// pointer** (`media.go:463-483`).
///
/// Keeping it is the point: the home `continue` bucket already excludes a
/// watched item, so clearing the flag returns the item to *continue where you
/// left off*. This is a different operation from [clearWatched], and they are
/// two functions rather than one with a boolean so the asymmetry is visible at
/// the call site.
WatchState setWatched(WatchState state, {required bool watched}) =>
    state.copyWith(watched: watched);

/// `DELETE /api/media/{id}/watched` — clears the flag **and** nils the pointer
/// (`media.go:485-499`).
///
/// This is the home page's "remove from completed". A leftover pointer would
/// bounce the item straight back into `continue`, which is why the pointer goes
/// too.
WatchState clearWatched(WatchState state) =>
    state.copyWith(watched: false, pointer: null);

/// `POST /api/media/{id}/favorite` (`media.go:394`).
WatchState setFavorite(WatchState state, {required bool favorite}) =>
    state.copyWith(favorite: favorite);

/// `POST /api/media/{id}/rating` (`media.go:417`) — 1-10 valid, **0 clears**.
///
/// Anything outside `0..10` throws rather than being clamped: the server
/// answers
/// it with `400 rating out of range` (`media.go:425`), so producing one is a
/// bug at the call site, and clamping would silently send a rating the user did
/// not choose.
///
/// The rating is independent of the resume engine — `applyProgress` never
/// touches it and [clearWatched] never clears it (`state/state.go:25-28`).
WatchState setRating(WatchState state, {required int rating}) {
  if (rating < 0 || rating > 10) {
    throw RangeError.range(rating, 0, 10, 'rating');
  }
  return state.copyWith(rating: rating);
}
