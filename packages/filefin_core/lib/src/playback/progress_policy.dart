import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/resume/engine.dart';
import 'package:filefin_core/src/resume/watch_state.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'progress_policy.freezed.dart';

/// What the server was last told, in the arithmetic the server itself uses.
///
/// [positionSeconds] is the **rounded** value, not the raw double, because that
/// is what the server stored and what the next report has to be compared
/// against. Keeping the double instead would let the client's idea of "30
/// seconds since the last report" drift from the pointer by up to half a second
/// each time.
@freezed
abstract class SentReport with _$SentReport {
  /// The last accepted report: [file], at [positionSeconds] whole seconds.
  const factory SentReport({
    required FileIndex file,
    required int positionSeconds,
  }) = _SentReport;
}

/// Why a report was not sent.
enum SkipReason {
  /// No usable duration yet — the file has not opened, or it is not seekable.
  notStarted,

  /// A checkpoint that has not moved far enough since the last report.
  withinInterval,

  /// A terminal event describing exactly what was already reported.
  unchanged,
}

/// Whether one playback tick should reach the server.
sealed class ProgressDecision {
  /// Allows the const subclasses below.
  const ProgressDecision();
}

/// Send [report] and, **only if it succeeds**, remember it.
final class SendProgress extends ProgressDecision {
  /// Send [report].
  const SendProgress(this.report);

  /// The body to POST.
  final ProgressReport report;
}

/// Send nothing, for [reason].
final class SkipProgress extends ProgressDecision {
  /// Skip for [reason].
  const SkipProgress(this.reason);

  /// Why nothing was sent.
  final SkipReason reason;
}

/// F9's entire reporting policy, as one pure function.
///
/// **The interval is measured in MEDIA seconds, never wall clock**, and that is
/// upstream's design rather than a simplification of it: its player compares
/// `Math.abs(el.currentTime - lastMark) >= 30`
/// (`web/src/views/library/Player.svelte`). Two things follow, and both are
/// features.
///
/// Nothing reports while playback is paused — the position is not moving, so
/// there is nothing new to say, and the `pause` trigger has already fired. And
/// the whole rule is testable with no clock, no `Timer` and no `fake_async`: a
/// test pushes positions and asserts decisions.
///
/// [lastSent] advances **only on a successful POST**. A report that failed is
/// therefore retried by the next trigger, with no queue and no timer (§1).
///
/// The rules, in order:
///
/// 1. a non-finite or non-positive duration, or a non-finite position, is
///    [SkipReason.notStarted]. This mirrors upstream's own
///    `if (!duration || !isFinite(duration)) return` and additionally protects
///    [roundReportedSeconds] from a value Dart's `.toInt()` throws on.
/// 2. a [ProgressEvent.checkpoint] sends when nothing has been sent, when the
///    file changed, or when the rounded position has moved at least
///    [intervalSecs] in **either** direction. A rewind is a move.
/// 3. every other event sends unless it describes the same file at the same
///    rounded second as the last one.
ProgressDecision decideReport({
  required FileIndex file,
  required double position,
  required double duration,
  required ProgressEvent event,
  required SentReport? lastSent,
  required int intervalSecs,
}) {
  if (!duration.isFinite || !position.isFinite || duration <= 0) {
    return const SkipProgress(SkipReason.notStarted);
  }

  final seconds = roundReportedSeconds(position);
  final sameFile = lastSent != null && lastSent.file == file;

  if (event.isTerminal) {
    if (sameFile && lastSent.positionSeconds == seconds) {
      return const SkipProgress(SkipReason.unchanged);
    }
  } else if (sameFile &&
      (seconds - lastSent.positionSeconds).abs() < intervalSecs) {
    return const SkipProgress(SkipReason.withinInterval);
  }

  return SendProgress(
    ProgressReport(
      file: file,
      position: position,
      duration: duration,
      event: event,
    ),
  );
}

/// Whether the detail payload must be re-read rather than predicted.
///
/// `applyProgress` reproduces the server exactly **except** on one class of
/// input, and this function is that exception made callable.
/// `WatchState.fromDetail` reads a `(0, 0)` view as "no pointer", which is
/// right for a stale ref and wrong for a genuine pointer at the very start of
/// a single-file item — so a report crossing 90% of such an item makes this
/// client predict `round(position)` where the server keeps `0`, and the
/// pointer only ever moving forward means the error persists until the detail
/// is fetched again.
///
/// It is scoped to `fileCount == 1` deliberately. With more than one file a
/// crossing advances the pointer to `(file + 1, 0)`, which is exactly
/// predictable and needs no round trip.
bool progressNeedsRefetch(ProgressReport report, {required int fileCount}) =>
    fileCount == 1 &&
    report.duration > 0 &&
    report.position / report.duration >= watchedThreshold;
