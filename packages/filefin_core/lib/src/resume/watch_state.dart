import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/models/media_detail.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'watch_state.freezed.dart';

/// Where playback of an item left off: a file and a whole-second offset into
/// it.
///
/// The server stores this as a **ref string** — `"SxE"`, `""` for a single-file
/// folder, or `"#N"` 1-based (`state/engine.go:17-31`). The client works in
/// indices, because `fileInfo.index` and `continueIndex` are what it is given.
/// The two agree for as long as the file list is stable, which is exactly as
/// long as one detail response describes.
///
/// Where they part company is when a file is renamed or renumbered between
/// sessions. Upstream's `indexOf` answers -1 for a ref it cannot find, and both
/// `Apply` and `View` then treat the pointer as absent. The index-space
/// equivalent is a [file] outside `0 ..< fileCount`, and the engine resolves it
/// the same way — see `resolveIndex`.
@freezed
abstract class ResumePointer with _$ResumePointer {
  /// A pointer at [file], [seconds] into it.
  const factory ResumePointer({
    required FileIndex file,
    required int seconds,
  }) = _ResumePointer;
}

/// One user's state for one media item, as `filefin_core` models it.
///
/// Mirrors upstream's `UserState` (`state/state.go:20-38`) minus `Updated`,
/// which is stamped by the writer and is the server's ordering key rather than
/// anything a client decides.
@freezed
abstract class WatchState with _$WatchState {
  /// A state with no pointer, nothing watched, no favourite and no rating.
  const factory WatchState({
    ResumePointer? pointer,
    @Default(false) bool watched,
    @Default(false) bool favorite,
    @Default(0) int rating,
  }) = _WatchState;

  const WatchState._();

  /// Reconstructs the state from a detail payload.
  ///
  /// The payload carries the **derived view** (`continueIndex`,
  /// `continueSeconds`), not the stored pointer, and the two are not the same
  /// thing: an unresolvable pointer is reported as `0`/`0`, indistinguishable
  /// from no pointer at all.
  ///
  /// So `0`/`0` is read here as **no pointer**. This is a tie-break, not a
  /// derivation: the two readings differ on exactly one class of input — a
  /// report that crosses 90% of an item with `fileCount == 1` — and everywhere
  /// else they agree. This one was chosen because a fresh or a stale pointer is
  /// the likelier ground truth behind `0`/`0`, and a stale pointer resolves to
  /// index -1 upstream, which is what an absent pointer resolves to.
  ///
  /// **The residual divergence persists; it does not close itself.** On a
  /// single-file item whose pointer genuinely sits at `(0, 0s)`, a crossing
  /// report makes this client predict `seconds = round(position)` where the
  /// server keeps `0` — and because the pointer only ever moves forward, the
  /// client stays ahead until a later report *exceeds* its own value.
  /// Transcribed from a live v0.20.3 session on a single-file film: after
  /// `{position: 95, duration: 100}` the client holds 95 and the server holds
  /// 0; after a rewind to `{position: 50}` the server moves to 50 and the
  /// client still holds 95. Once the user rewinds, the optimistic value is
  /// simply wrong, and `watched` being set does not hide it — un-watching
  /// returns the item to the `continue` row with that stale offset.
  ///
  /// A consumer must therefore **re-read the detail** after a crossing report
  /// on a single-file item rather than trust the prediction. M4's progress
  /// reporter is the first consumer this binds; STATE.md carries it as a known
  /// limitation.
  ///
  /// [MediaDetail.rating] is **not** clamped by the server on read — only on
  /// write — so a hand-edited `meta.json` can serve `rating: 99` while
  /// `POST .../rating {"rating": 99}` answers `400 rating out of range`.
  /// Copying it through unchecked would build a `WatchState` that this
  /// library's own `setRating` refuses, so anything outside `0..10` is read as
  /// **0, unrated** — upstream's own word for "no rating"
  /// (`state/state.go:29`). The wire model keeps the raw value; §8 tolerance
  /// belongs there, and the invariant that every state we construct is one
  /// every mutator accepts belongs here.
  factory WatchState.fromDetail(MediaDetail detail) => WatchState(
    pointer: detail.continueIndex == 0 && detail.continueSeconds == 0
        ? null
        : ResumePointer(
            file: FileIndex(detail.continueIndex),
            seconds: detail.continueSeconds,
          ),
    watched: detail.watched,
    favorite: detail.favorite,
    // `isNegative` rather than `>= 0`, and that is not a style choice. With the
    // fallback also being 0, `rating >= 0` and `rating > 0` produce the same
    // answer for every input — the mutation gate reported it as a survivor and
    // it is genuinely equivalent, so the operator was removed rather than
    // excluded. An exclusion is a piece of code the gate stops asking about; a
    // predicate with no boundary to get wrong is better.
    rating: detail.rating.isNegative || detail.rating > 10 ? 0 : detail.rating,
  );
}

/// One playback report, as `POST /api/media/{id}/progress` sends it.
///
/// The wire body also carries `event`, which the engine ignores — nothing in
/// `state.Apply` reads it. It is not modelled here: a field no code reads is a
/// dead branch (§5), and it arrives at M4 with the progress reporter that
/// actually sends it, for the same reason `progressIntervalSecs` does.
@freezed
abstract class ProgressReport with _$ProgressReport {
  /// A report of [position] seconds into a [duration]-second [file].
  const factory ProgressReport({
    required FileIndex file,
    required double position,
    required double duration,
  }) = _ProgressReport;
}

/// The watch state a detail view renders — upstream's `WatchView`,
/// `state/engine.go:88-93`.
@freezed
abstract class WatchView with _$WatchView {
  /// The derived view over a file list of a known length.
  const factory WatchView({
    required bool watched,
    required FileIndex continueIndex,
    required int continueSeconds,
    required List<bool> perFile,
  }) = _WatchView;
}
