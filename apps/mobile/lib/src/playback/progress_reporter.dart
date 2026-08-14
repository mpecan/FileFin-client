import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';

/// Why the reporter gave up on an item, when it has.
enum ReportStop {
  /// The session ended and could not be renewed. Reporting resumes after a
  /// successful re-auth; nothing is lost but the reports in between.
  signedOut,

  /// The server rejected the report itself — `bad file index`, which means the
  /// item's file list changed under us. Retrying posts the same rejected body
  /// forever, so it stops and the screen says so.
  rejected,
}

/// F9, with no timer and no clock anywhere.
///
/// **Every decision is `decideReport`'s**, a pure function over **media**
/// seconds, which is what makes this deterministic: a test pushes positions and
/// asserts requests, with no `fake_async` and nothing to flake.
///
/// [lastSent] advances **only after a successful POST**, so a failed report is
/// retried by the next trigger with no queue and no backoff (§1). The cost is
/// stated rather than hidden: a report lost to a flaky network is lost, and the
/// next checkpoint carries the newer position anyway.
class ProgressReporter {
  /// Reports [media]'s progress through [api], every [intervalSecs] of media.
  ProgressReporter({
    required this.api,
    required this.media,
    required this.intervalSecs,
    required this.fileCount,
    required WatchState initial,
  }) : state = initial;

  /// Where reports go.
  final LibraryApi api;

  /// Which item is playing.
  final MediaId media;

  /// How far playback must move before a checkpoint is worth a request.
  final int intervalSecs;

  /// How many files the item has — what `applyProgress` calls `refs`.
  final int fileCount;

  /// The optimistic local state, folded through the **same engine the server
  /// runs**.
  ///
  /// This is F9's "reflect resulting watched/continue changes locally without a
  /// full refetch": `applyProgress` is validated against 601 vectors captured
  /// from upstream's own `state.Apply`, so what this holds after a successful
  /// report is what the server holds.
  WatchState state;

  /// Whether the prediction above is known to have diverged.
  ///
  /// Latched, never cleared here: `progressNeedsRefetch` marks the one input
  /// class where `applyProgress` cannot match the server — a report crossing
  /// 90% of a **single-file** item, where `(0, 0)` is ambiguous on the wire.
  /// The screen re-reads the detail rather than trusting the prediction, which
  /// is what discharges M1's known limitation.
  bool needsDetailRefetch = false;

  /// Why reporting stopped, or null while it is running.
  ReportStop? stopped;

  SentReport? _lastSent;

  /// What the server was last told, for the interval comparison.
  SentReport? get lastSent => _lastSent;

  /// Reporting resumes: called after a successful re-auth.
  void resume() => stopped = null;

  /// Considers one playback tick, and reports it if the policy says so.
  ///
  /// Returns the decision, so a caller can assert on it and a test does not
  /// have to infer intent from a request count.
  ///
  /// **Nothing here ever blocks playback or shows a modal.** A failed report is
  /// a fact about the network, not about the film.
  Future<ProgressDecision> report({
    required FileIndex file,
    required Duration position,
    required Duration duration,
    required ProgressEvent event,
  }) async {
    if (stopped != null) return const SkipProgress(SkipReason.unchanged);

    final decision = decideReport(
      file: file,
      position: position.inMilliseconds / 1000,
      duration: duration.inMilliseconds / 1000,
      event: event,
      lastSent: _lastSent,
      intervalSecs: intervalSecs,
    );
    if (decision is! SendProgress) return decision;

    try {
      await api.postProgress(media, decision.report);
    } on RequestCancelled {
      // Not a failure: the screen went away. Dropping it silently is the whole
      // reason that variant is separate from every other one.
      return decision;
    } on SessionExpired {
      stopped = ReportStop.signedOut;
      return decision;
    } on BadRequest {
      stopped = ReportStop.rejected;
      return decision;
    } on FileFinApiException {
      // Everything else keeps `lastSent` where it was, so the next trigger
      // retries with a newer position. No queue, no timer.
      return decision;
    }

    _lastSent = SentReport(
      file: decision.report.file,
      positionSeconds: roundReportedSeconds(decision.report.position),
    );
    state = applyProgress(state, decision.report, fileCount: fileCount);
    needsDetailRefetch =
        needsDetailRefetch ||
        progressNeedsRefetch(decision.report, fileCount: fileCount);
    return decision;
  }
}
