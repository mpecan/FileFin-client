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
  /// [MediaDetail.rating] is **copied through exactly as the server reports
  /// it**, including a value outside `0..10`.
  ///
  /// The server validates a rating on write and not on read, so a hand-edited
  /// `meta.json` really does serve `rating: 99` while
  /// `POST .../rating {"rating": 99}` answers `400 rating out of range`
  /// (M6.0/E-6). This class mirrors upstream's `UserState`
  /// (`state/state.go:20-38`), and what upstream is storing in that case is 99.
  ///
  /// **It used to read anything outside `0..10` as 0, and that lost data.**
  /// `applyWatchState` folds `state.rating` back onto the payload, and all of
  /// `setFavorite`, `setWatched` and `clearWatched` round-trip through here —
  /// so on an item the server reports as 99, tapping the heart made the screen
  /// say *Not rated* and deleted the notice explaining the value, while the
  /// server still held 99 (M6.R/P1.4). The write it followed is a total
  /// assignment to `favorite` in the server's own fold and touches no rating at
  /// all, so the prediction was simply wrong.
  ///
  /// The invariant it was defending — "every state we construct is one every
  /// mutator accepts" — did not need defending. `setRating` range-checks its
  /// **argument**, not `state.rating`, and no other mutator reads the rating,
  /// so no mutator refuses a state carrying 99. The only caller that could have
  /// tripped it was `setRating(state, rating: state.rating)`, which nothing
  /// does: the picker offers `0..10` and nothing else.
  factory WatchState.fromDetail(MediaDetail detail) => WatchState(
    pointer: detail.continueIndex == 0 && detail.continueSeconds == 0
        ? null
        : ResumePointer(
            file: FileIndex(detail.continueIndex),
            seconds: detail.continueSeconds,
          ),
    watched: detail.watched,
    favorite: detail.favorite,
    rating: detail.rating,
  );
}

/// Why a progress report is being sent — the wire body's `event` field.
///
/// **Four of the five are upstream's own strings**, read off its player:
/// `checkpoint`, `pause`, `ended` and `stop`
/// (`web/src/views/library/Player.svelte`). `seek` is ours, and adding it is
/// safe in the strongest sense available — `state.Apply` never reads `event` at
/// all, so no value of it can change what the server stores. It is sent because
/// a server log that says which trigger fired is worth more than one that says
/// `checkpoint` five different ways.
enum ProgressEvent {
  /// Playback simply advanced past the reporting interval.
  checkpoint,

  /// The user paused, or the OS backgrounded the app (NF6).
  pause,

  /// A seek completed. **Ours, not upstream's.**
  seek,

  /// Playback reached the end of the file.
  ended,

  /// The player is going away — the route closed, or the item changed.
  stop;

  /// The exact token the wire body carries.
  String get wire => name;

  /// Whether this event reports regardless of how long ago the last one was.
  ///
  /// The interval exists to stop a *continuous* position from reporting on
  /// every tick. Every other trigger is a discrete thing that just happened and
  /// may be the last chance to record it — a `pause` that the OS turns into a
  /// kill is the whole reason NF6's pointer survives.
  bool get isTerminal => this != ProgressEvent.checkpoint;
}

/// One playback report, as `POST /api/media/{id}/progress` sends it.
///
/// [event] is on the wire and **invisible to the engine**: nothing in
/// `state.Apply` reads it, which is why `applyProgress` ignores it too and why
/// adding it here changed no captured vector. It defaults to
/// [ProgressEvent.checkpoint] so every existing construction keeps its meaning.
@freezed
abstract class ProgressReport with _$ProgressReport {
  /// A report of [position] seconds into a [duration]-second [file].
  const factory ProgressReport({
    required FileIndex file,
    required double position,
    required double duration,
    @Default(ProgressEvent.checkpoint) ProgressEvent event,
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
