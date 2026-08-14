part of 'player_controller.dart';

// What the player hands back, and what it says when something goes wrong.
// `player_controller.dart`'s `part` directive says why this is a part.

/// What one playback session leaves behind for the screen that opened it.
///
/// **What the screen that pushed the player has to know on the way out**, so it
/// can reflect the watched and continue changes without a full refetch.
///
/// Without a reader, the fold is computed, validated against 601 captured
/// vectors and thrown away — and the detail screen behind the player shows a
/// resume offset from before playback started.
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
  /// is what makes the no-refetch path honest rather than optimistic.
  final bool needsDetailRefetch;

  /// Whether the SERVER accepted at least one progress report this session.
  ///
  /// Distinct from [state], which is the optimistic fold and exists whether or
  /// not anything was posted. This is `lastSent != null`, set only after a
  /// `204` — so it means the server re-stamped `updated`, which orders all
  /// three home rows (`docs/field-notes.md`). The detail route pops it, and it
  /// is why watching something moves it out of *Continue watching*.
  ///
  /// Defaulted rather than required: a test exercising the fold is not making
  /// a claim about the home rows.
  final bool wrote;
}

/// The sentence a playback failure shows, and whether it needs a sign-in.
///
/// A tuple rather than a reach into `error_presentation.dart`'s `ErrorMessage`:
/// the player shows one line over the video, not a full panel with a Retry
/// button, and the two surfaces want different things from the same error.
///
/// **There is no `_` arm, and its absence is the point.** It had one until
/// once, and it was the hole in an alarm three other switches sounded
/// correctly when `TranscodingDisabled` landed: this one kept compiling, and
/// would have put `Playback could not start: TranscodingDisabled: …` on the
/// banner this is actually about. The generic sentence is a **grouped arm**
/// rather than a default, so a new variant stays a compile error here.
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
