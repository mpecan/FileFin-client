part of 'player_controller.dart';

// What the player hands back, and what it says when something goes wrong.
// `player_controller.dart`'s `part` directive says why this is a part.

/// What one playback session leaves behind for the screen that opened it.
///
/// **This is F9's second clause made into a value someone receives** — "reflect
/// resulting watched/continue changes locally without a full refetch". Until
/// M4.R/P3 `ProgressReporter.state` and `needsDetailRefetch` had no production
/// reader at all: the fold was computed, validated against 601 captured vectors
/// and thrown away, `MediaDetailPage` loaded once in `initState` and never
/// again, and the detail screen behind the player showed a resume offset from
/// before playback started. M1's divergence latch discharged nothing because
/// nothing read it.
@immutable
class PlaybackOutcome {
  /// The session ended with [state], needing a refetch or not.
  const PlaybackOutcome({
    required this.state,
    required this.needsDetailRefetch,
    this.wrote = false,
  });

  /// The optimistic watch state, folded through the server's own engine.
  final WatchState state;

  /// Whether [state] is known to have diverged and must be re-read instead.
  ///
  /// True only for the one input class `applyProgress` provably cannot match —
  /// a report crossing 90% of a single-file item, where `(0, 0)` is ambiguous
  /// on the wire. Everywhere else the prediction IS the server's answer, which
  /// is what makes the no-refetch half of F9 honest rather than optimistic.
  final bool needsDetailRefetch;

  /// Whether the SERVER accepted at least one progress report this session.
  ///
  /// Distinct from [state], which is the optimistic fold and exists whether or
  /// not anything was posted. This one is `lastSent != null`, which the
  /// reporter sets only after a `204` — so it means the server re-stamped
  /// `updated`, and `updated` is the ordering key of all three home rows
  /// (M6.0/E-3). The detail route pops it, and it is the reason watching
  /// something now moves it out of *Continue watching* on Home rather than
  /// leaving it there in its pre-playback position for the rest of the session
  /// (M6.R/P1.2).
  ///
  /// Defaulted rather than required: a test constructing an outcome to exercise
  /// F9's fold is not making a claim about the home rows, and the two cases
  /// that ARE about them say so explicitly.
  final bool wrote;
}

/// The sentence a playback failure shows, and whether it needs a sign-in.
///
/// A tuple rather than a reach into `error_presentation.dart`'s `ErrorMessage`:
/// the player shows one line over the video, not a full panel with a Retry
/// button, and the two surfaces want different things from the same error.
///
/// **There is no `_` arm, and its absence is the point.** This function had one
/// until M5.1, and it was a hole in an alarm three other switches were sounding
/// correctly: `error_presentation.dart`, `error_presentation_test.dart` and
/// `error_mapper_test.dart` all stopped compiling when `TranscodingDisabled`
/// landed and this one did not (measured, M5.0/E-J). It would have rendered
/// `Playback could not start: TranscodingDisabled: … turned off` on the player
/// banner — the surface F12 is actually about — with nothing to say so. The
/// generic sentence is now a **grouped arm** rather than a default, so it still
/// covers everything with no wording of its own while a new variant remains a
/// compile error here.
(String, bool) describeApiFailure(FileFinApiException error) => switch (error) {
  SessionExpired() => (
    'Your session ended. Sign in again to keep playing.',
    true,
  ),
  TranscodingDisabled() => (
    'This file needs transcoding and the server has it turned off.',
    false,
  ),
  BadRequest(:final body) => ('The server refused that file: $body', false),
  NotFound() => ('That file is not on the server any more.', false),
  RequestTimedOut() ||
  RequestCancelled() ||
  ConnectionFailed() ||
  CacheUnavailable() ||
  RateLimited() ||
  MalformedIdentifier() ||
  InvalidCredentials() ||
  NotAFileFinServerResponse() ||
  MalformedResponse() ||
  ServerFailure() ||
  CertificateNotTrusted() ||
  CertificatePinMismatch() => ('Playback could not start: $error', false),
};
