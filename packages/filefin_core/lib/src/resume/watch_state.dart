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
  /// So `0`/`0` is read here as **no pointer**, and that choice is the one that
  /// matches `Apply`. A stale pointer resolves to index -1 upstream, which is
  /// what an absent pointer resolves to; modelling it as a pointer at index 0
  /// would disagree with the server on every subsequent report. The cost is the
  /// one case where a real pointer genuinely sits at `(0, 0s)`: crossing 90%
  /// of a single-file item would then predict `seconds = round(position)`
  /// where the server keeps `0`. The item is `watched` by then and has left
  /// every `continue` row, so nothing reads the difference.
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
