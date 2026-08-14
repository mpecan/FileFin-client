import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/models/media_detail.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'watch_state.freezed.dart';

/// Where playback of an item left off: a file and a whole-second offset.
///
/// The client works in indices; the server stores a ref string. They
/// agree for as long as the file list is stable — that is, for as long as one
/// detail response describes. A [file] outside `0..< fileCount` is a pointer
/// that no longer resolves, and `resolveIndex` treats it as absent, which is
/// what upstream's `indexOf` does with a ref it cannot find.
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
/// Mirrors upstream's `UserState` minus `Updated`,
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
  /// `continueSeconds`), never the stored pointer, so `0`/`0` is ambiguous and
  /// is read here as no pointer. On a single-file item whose pointer genuinely
  /// sits at zero, that leaves the client ahead of the server until the detail
  /// is re-read.
  ///
  /// [MediaDetail.rating] is copied through exactly as reported, including a
  /// value outside `0..10`.
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
///. `seek` is ours, and adding it is
/// safe in the strongest sense available — `state.Apply` never reads `event` at
/// all, so no value of it can change what the server stores. It is sent because
/// a server log that says which trigger fired is worth more than one that says
/// `checkpoint` five different ways.
enum ProgressEvent {
  /// Playback simply advanced past the reporting interval.
  checkpoint,

  /// The user paused, or the OS backgrounded the app.
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
  /// kill is the whole reason the pointer survives.
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
/// `state/engine.go`.
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
