import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/resume/engine.dart';
import 'package:filefin_core/src/resume/watch_state.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'progress_policy.freezed.dart';

/// What the server was last told, in the arithmetic the server itself uses.
///
/// [positionSeconds] is the **rounded** value, in the server's own arithmetic,
/// so the next report is compared on the same footing; a raw double would drift
/// from the pointer by up to half a second per report.
///
/// **It is what this client last SENT, not what the server stored.** The two
/// part company whenever the engine does something other than store the number
/// — a crossing past 90% moves the pointer to the next file at zero while this
/// still holds the position that caused it. The dedupe wants precisely "the
/// last thing we said", so it is right either way.
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
/// **The interval is MEDIA seconds, never wall clock** — upstream's design
/// (`docs/field-notes.md`), so nothing reports while paused and the whole rule
/// is testable with no clock. [lastSent] advances **only on a successful
/// POST**, so a failed report is retried by the next trigger (§1).
///
/// The rules in order: a non-finite or non-positive duration, or non-finite
/// position, is [SkipReason.notStarted]; a [ProgressEvent.checkpoint] sends
/// when nothing has been sent, the file changed, or the rounded position moved
/// at least [intervalSecs] **either way** (a rewind is a move); every other
/// event sends unless it repeats the last file and rounded second.
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
/// `applyProgress` reproduces the server exactly except on one class of input,
/// and this is that exception made callable — D15 has the case and its cost.
///
/// Scoped to `fileCount == 1` deliberately: with more than one file a crossing
/// advances the pointer to `(file + 1, 0)`, which is exactly predictable and
/// needs no round trip.
bool progressNeedsRefetch(ProgressReport report, {required int fileCount}) =>
    fileCount == 1 &&
    report.duration > 0 &&
    report.position / report.duration >= watchedThreshold;
