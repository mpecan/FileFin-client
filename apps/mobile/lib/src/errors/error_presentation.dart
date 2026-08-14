import 'package:filefin_api/filefin_api.dart';
import 'package:meta/meta.dart';

/// One failure, phrased for the person looking at it.
@immutable
class ErrorMessage {
  /// A short line naming what happened.
  const ErrorMessage({
    required this.title,
    required this.detail,
    this.retryable = false,
    this.needsSignIn = false,
  });

  /// The headline. Short enough to read at a glance.
  final String title;

  /// The sentence that says what to do about it, or what is known.
  final String detail;

  /// Whether repeating the same request could plausibly work.
  ///
  /// It gates the retry affordance, and getting it wrong is worse than not
  /// having one: a retry button on a rate-limit refusal invites mashing it
  /// against a limiter that locks the account for fifteen minutes.
  final bool retryable;

  /// Whether the right next step is the sign-in screen.
  final bool needsSignIn;
}

/// Turns one of `filefin_api`'s errors into words a person can act on.
///
/// **The switch is exhaustive and has no default arm, and that is the design.**
/// Adding `TranscodingDisabled` stopped this compiling; a default would have
/// said "something went wrong" for the one error that has to be named exactly.
///
/// Every URL goes through `redactUserInfo`: a message is a log line waiting to
/// happen and a saved-server URL is typed by a user.
///
/// **A message names the cause it actually has.** `SessionExpired` does not
/// mean a server restart, which renewal handles silently; it means there is no
/// stored session, or no password.
ErrorMessage describeApiError(FileFinApiException error) => switch (error) {
  RequestTimedOut(:final phase, :final requested) => ErrorMessage(
    title: 'The server did not answer in time',
    detail:
        '${redactUserInfo(requested).host} timed out while '
        '${phase.description}. It may be starting up, or the network may be '
        'slow.',
    retryable: true,
  ),

  // Never rendered — AsyncController drops cancellation — but present, because
  // exhaustiveness is what makes a new variant a compile error.
  RequestCancelled() => const ErrorMessage(
    title: 'Cancelled',
    detail: 'That request was cancelled before it finished.',
  ),

  ConnectionFailed(:final requested, :final cause) => ErrorMessage(
    title: 'Cannot reach the server',
    detail: cause == null
        ? 'Nothing answered at ${redactUserInfo(requested).host}. Check the '
              'address and that you are on the right network.'
        : 'Nothing answered at ${redactUserInfo(requested).host}: $cause',
    retryable: true,
  ),

  // The 401 retry already ran, so retrying repeats what did not work.
  SessionExpired() => const ErrorMessage(
    title: 'Please sign in again',
    detail:
        'Your session ended and there is no saved password to renew it with. '
        'A session that can be renewed is renewed without asking, so getting '
        'here means typing the password once more.',
    needsSignIn: true,
  ),

  // NOT retryable: the arguments were unusable, so the same request fails
  // again. Today's is `bad file index` — the file list changed under us.
  BadRequest(:final body) => ErrorMessage(
    title: 'The server refused that request',
    detail:
        'The server said: $body. This usually means the item changed on the '
        'server since it was opened — go back and open it again.',
  ),

  NotFound(:final requested) => ErrorMessage(
    title: 'Not on the server any more',
    detail:
        'The server has no such item. It may have been removed from '
        '${redactUserInfo(requested).host} since this list was loaded.',
  ),

  // "possibly", not "rebuilding": media.go writes `cache unavailable`
  // for ANY ensureDB failure, so promising a rebuild promises an end that may
  // never come.
  CacheUnavailable() => const ErrorMessage(
    title: 'The library is unavailable',
    detail:
        "The server's library cache is unavailable, possibly because it is "
        'rebuilding. Trying again shortly usually works.',
    retryable: true,
  ),

  // Zero means "we did not parse the header", not "retry now" (errors.dart);
  // "wait 0 seconds" would be a guess presented as a fact.
  RateLimited(:final retryAfter) => ErrorMessage(
    title: 'Too many attempts',
    detail: retryAfter == Duration.zero
        ? 'The server is refusing sign-in attempts for a while. Five wrong '
              'passwords lock an account for fifteen minutes.'
        : 'The server is refusing sign-in attempts for another '
              '${retryAfter.inSeconds} seconds.',
  ),

  // The value came off the wire (`MediaSummary.id` defaults to `MediaId('')`
  // so blaming the user sends them hunting a typo they never made.
  MalformedIdentifier(:final field, :final value) => ErrorMessage(
    title: 'The server sent an item we cannot open',
    detail:
        'It arrived with no usable $field ("$value"), so there is no address '
        'to ask for. This is a problem with the library on the server.',
  ),

  // auth.go runs one bcrypt compare against a dummy hash for an
  // unknown account, so nothing separates the three causes. Guessing would be
  // inventing information.
  InvalidCredentials() => const ErrorMessage(
    title: 'That did not work',
    detail:
        'The server refused that username and password. It will not say which '
        'of the two was wrong, or whether the account is locked.',
  ),

  NotAFileFinServerResponse(:final requested, :final contentType) =>
    ErrorMessage(
      title: 'That address is not a FileFin server',
      detail:
          '${redactUserInfo(requested).host} answered, but with '
          '${contentType ?? 'no content type'} instead of JSON — so it is '
          'not a FileFin server, or not one at this path.',
    ),

  // The opposite of the variant above: that one means "wrong address", this
  // one means "right address, unreadable reply". Collapsing them would send a
  // user to check an address that is correct.
  MalformedResponse(:final problem) => ErrorMessage(
    title: 'The server sent something unexpected',
    detail:
        'The reply was not the shape this app understands: $problem. The '
        'server may be a version this app has not been checked against.',
  ),

  // Not retryable: the setting is the server's.
  TranscodingDisabled(:final requested) => ErrorMessage(
    title: 'This file needs transcoding',
    detail:
        '${redactUserInfo(requested).host} has transcoding turned off, and '
        'this file cannot be played without it. Nothing this app can change '
        'will help: someone with admin access to the server has to turn it '
        'back on.',
  ),

  ServerFailure(:final statusCode, :final requested) => ErrorMessage(
    title: 'The server reported a problem',
    detail:
        '${redactUserInfo(requested).host} answered $statusCode. If it keeps '
        "happening, the server's own log will say more than this app can.",
    retryable: true,
  ),

  // The fingerprint is shown and accepted deliberately; a retry button
  // would invite mashing it until something gives.
  CertificateNotTrusted(:final fingerprint, :final subject, :final validTo) =>
    ErrorMessage(
      title: "This server's certificate is not trusted",
      detail:
          'It identifies itself as $subject with fingerprint $fingerprint, '
          'valid until ${validTo.toIso8601String().split('T').first}. '
          'Self-hosted servers commonly use a certificate nobody else '
          'vouches for; check the fingerprint before accepting it.',
    ),

  // The loud half: a CHANGED fingerprint blocks rather than re-accepting,
  // shows both values, and says "refused" — never "nothing was sent", which
  // `errors_certificates.dart` measured at 106 bytes already gone.
  CertificatePinMismatch(:final expected, :final actual) => ErrorMessage(
    title: "This server's certificate has changed",
    detail:
        'It was accepted as $expected and now presents $actual. That can mean '
        'the certificate was renewed — or that something is impersonating the '
        'server. The connection was refused.',
  ),
};
