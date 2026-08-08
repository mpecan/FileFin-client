/// Everything `filefin_api` throws, as one sealed hierarchy.
///
/// The hierarchy is **total**: no request path may let a `DioException`, a
/// `SocketException` or a `FormatException` escape this package. A caller that
/// has to catch two vocabularies ends up catching `Object`, and then a bug in
/// the client is indistinguishable from a server the user typed wrong.
///
/// It is also **exactly as large as M2 needs** (§1, §5). `dead_types` fails a
/// `sealed` variant nobody constructs outside its declaring file, so a variant
/// arrives in the commit that first produces it and not before. What is
/// deliberately absent, with the milestone that adds it:
///
/// - `TranscodingDisabled` (415) — M5, where F12's wording is the whole point
///   of the variant.
/// - `BadRequest` (400) — M4 (`bad file index`) and M6 (`rating out of
///   range`). At M2 the only 400 the server can produce is `bad category id`,
///   and `CategoryId` is an `int`, so nothing can construct that request.
/// - 403 — never. It is admin-only, and C4 forbids calling an admin route.
///
/// **Hand-written, not `@freezed`.** None of these needs `copyWith` or JSON,
/// and §9 forbids a secret-bearing type carrying freezed's default `toString`
/// — which prints every field. Writing the messages by hand is what lets each
/// one say the thing a user or a log reader actually needs.
library;

/// Strips `user:password@` from a URL before it reaches a message.
///
/// Every variant below echoes the URL it was requesting, and a message is a
/// log line waiting to happen (§9, NF4). Nothing in this package puts
/// credentials in a URL, but a *saved server* URL is typed by the user and
/// `https://sam:hunter2@host/` is a thing people type. `Uri.removeFragment`
/// has no sibling for userInfo, so the reconstruction is explicit.
Uri redactUserInfo(Uri url) =>
    url.userInfo.isEmpty ? url : url.replace(userInfo: '');

/// Which stage of a request ran out of time (NF5).
///
/// The three are worth distinguishing because they mean different things to a
/// user: a connect timeout is "I cannot reach this server", a receive timeout
/// is "this server is answering too slowly", and they lead to different next
/// actions.
enum RequestPhase {
  /// The TCP/TLS connection was never established.
  connect,

  /// The request body stalled on the way out.
  send,

  /// The response stalled on the way back.
  receive;

  /// A phrase that reads correctly inside an error message.
  String get description => switch (this) {
    RequestPhase.connect => 'connecting',
    RequestPhase.send => 'sending the request',
    RequestPhase.receive => 'reading the response',
  };
}

/// The base of everything this package throws.
///
/// It holds no fields: `MalformedIdentifier` (M2.6) is raised *before* a URL
/// exists, so a `requested` on the base would have to be nullable and every
/// consumer would branch on it.
sealed class FileFinApiException implements Exception {
  /// Allows the variants below to be `const`.
  const FileFinApiException();
}

/// A request that ran out of time in [phase] (NF5).
final class RequestTimedOut extends FileFinApiException {
  /// The request to [requested] timed out while [phase].
  const RequestTimedOut(this.phase, this.requested);

  /// Which stage ran out of time.
  final RequestPhase phase;

  /// The URL that was being requested.
  final Uri requested;

  @override
  String toString() =>
      'RequestTimedOut: timed out ${phase.description} '
      '${redactUserInfo(requested)}';
}

/// A request the caller cancelled through its `CancelToken` (NF5).
///
/// Not a failure. It is separate from every other variant precisely so a UI
/// can drop it silently instead of showing "something went wrong" when the
/// user simply navigated away.
final class RequestCancelled extends FileFinApiException {
  /// The request to [requested] was cancelled by its caller.
  const RequestCancelled(this.requested);

  /// The URL that was being requested.
  final Uri requested;

  @override
  String toString() =>
      'RequestCancelled: ${redactUserInfo(requested)} was cancelled';
}

/// The server could not be reached at all: refused, unresolvable, or reset.
///
/// Also the landing place for a `DioExceptionType` this package does not
/// recognise. dio gains exception types between minor versions, and the exact
/// pin in `pubspec.yaml` is what turns that into a review event; until then a
/// new type must still arrive as one of ours rather than escaping raw.
final class ConnectionFailed extends FileFinApiException {
  /// [requested] could not be reached; [cause] is whatever dio carried.
  const ConnectionFailed(this.requested, {this.cause});

  /// The URL that was being requested.
  final Uri requested;

  /// The underlying error, kept so a UI can show the OS's own words.
  final Object? cause;

  @override
  String toString() =>
      'ConnectionFailed: could not reach ${redactUserInfo(requested)}'
      '${cause == null ? '' : ' ($cause)'}';
}

/// A `401` that re-authentication did not fix, or could not be attempted.
///
/// **A 401 on its own is routine** (SPEC.md L1): sessions live in the server's
/// memory and die with the process, so F3 re-authenticates and retries once.
/// This variant is what is left when that has already happened — the retry
/// also 401'd, or no stored password existed to retry with. It is the only
/// shape of 401 a caller ever sees.
///
/// The name matches `secret_tostring`'s watch list, and the explicit
/// `toString` below is the right answer to that rather than a rename: this
/// type genuinely sits next to session handling, and a future field on it
/// would be exactly the kind that must not print.
final class SessionExpired extends FileFinApiException {
  /// The session used for [requested] is gone and could not be renewed.
  const SessionExpired(this.requested);

  /// The URL that was being requested.
  final Uri requested;

  @override
  String toString() =>
      'SessionExpired: not signed in for ${redactUserInfo(requested)}';
}

/// A real `404` from a handler that matched — an unknown id or file index.
///
/// It is never a routing 404: this server answers an unmatched path with the
/// SPA catch-all's `200 text/html` (`docs/server-api.md`, "Conventions"), so a
/// mistyped route arrives as `NotAFileFinServerResponse` instead.
final class NotFound extends FileFinApiException {
  /// [requested] matched a handler, which then found nothing.
  const NotFound(this.requested);

  /// The URL that was being requested.
  final Uri requested;

  @override
  String toString() => 'NotFound: ${redactUserInfo(requested)}';
}

/// A `503`: the server's SQLite cache is being rebuilt or is unreadable.
///
/// Transient and self-healing, which is why it is not folded into
/// [ServerFailure] — the correct UI is "try again in a moment", not "something
/// is broken".
final class CacheUnavailable extends FileFinApiException {
  /// [requested] could not be served because the cache was unavailable.
  const CacheUnavailable(this.requested);

  /// The URL that was being requested.
  final Uri requested;

  @override
  String toString() =>
      'CacheUnavailable: the server cache is rebuilding '
      '(${redactUserInfo(requested)})';
}

/// A `429` from the login rate limiter (`loginlimit.go:15-27`).
///
/// Five failures against one account in fifteen minutes lock that account for
/// fifteen minutes; twenty against one IP in five minutes lock the IP. The
/// limiter lives in the server's memory and dies with the process.
final class RateLimited extends FileFinApiException {
  /// Rate limited on [requested]; wait [retryAfter] before trying again.
  const RateLimited(this.retryAfter, this.requested, {this.rawRetryAfter});

  /// How long to wait, or [Duration.zero] when the header did not parse.
  ///
  /// **Zero means "we do not know", not "retry immediately".** The server
  /// sends whole seconds and only whole seconds (`auth.go:149` is
  /// `int(retry.Seconds()) + 1`), so anything else is a proxy in the middle or
  /// a server we did not verify against — and inventing a duration from a
  /// value we failed to parse would be a guess presented as a fact.
  /// [rawRetryAfter] survives so a human can read what actually arrived.
  final Duration retryAfter;

  /// The `Retry-After` header exactly as received, or null when absent.
  final String? rawRetryAfter;

  /// The URL that was being requested.
  final Uri requested;

  @override
  String toString() =>
      'RateLimited: ${redactUserInfo(requested)} refused for '
      '${retryAfter.inSeconds}s (Retry-After: ${rawRetryAfter ?? 'absent'})';
}

/// `POST /api/login` said no: wrong password, unknown account, or locked.
///
/// **The three are indistinguishable by design** (`auth.go:157-169`): the
/// server always runs exactly one bcrypt compare, against a dummy hash when the
/// account does not exist, so neither the body nor the timing tells them apart.
/// A client that guessed between them would be inventing information.
///
/// It is deliberately not `SessionExpired`. A 401 from `/api/login` is the one
/// place where a 401 does **not** mean L1, and re-authenticating in response to
/// it is an infinite loop against a limiter that locks the account after five
/// tries.
final class InvalidCredentials extends FileFinApiException {
  /// [requested] rejected the username and password it was given.
  const InvalidCredentials(this.requested);

  /// The login URL that refused.
  final Uri requested;

  @override
  String toString() =>
      'InvalidCredentials: ${redactUserInfo(requested)} rejected that username '
      'and password';
}

/// The server's certificate is not trusted and nothing is pinned (F15).
///
/// **The trust-on-first-use prompt, not a failure to report.** Self-signed and
/// private-CA certificates are the common case for a self-hosted server, so
/// this is the normal first connection to one. The UI shows [fingerprint] —
/// alongside [subject], [issuer] and [validTo], which are what let a user tell
/// "my own server" from "something else" — and if they accept it, the caller
/// writes the pin and rebuilds the client.
///
/// Nothing was sent. The refusal happens inside the TLS handshake, so the
/// server received no request at all and no cookie left the device.
final class CertificateNotTrusted extends FileFinApiException {
  /// [requested]'s certificate is untrusted and unpinned.
  const CertificateNotTrusted(
    this.requested, {
    required this.fingerprint,
    required this.subject,
    required this.issuer,
    required this.validTo,
  });

  /// The URL that was being requested.
  final Uri requested;

  /// The SHA-256 the user is being asked to compare, in colon-hex.
  final String fingerprint;

  /// The certificate's subject, e.g. `/CN=filefin.lan`.
  final String subject;

  /// The certificate's issuer; equal to [subject] for a self-signed one.
  final String issuer;

  /// When the certificate stops being valid.
  final DateTime validTo;

  @override
  String toString() =>
      'CertificateNotTrusted: ${redactUserInfo(requested)} presented an '
      'untrusted certificate ($subject, issued by $issuer, valid to '
      '${validTo.toIso8601String()}). SHA-256 $fingerprint';
}

/// A pinned server presented a **different** certificate (F15).
///
/// The loud, blocking half of F15, and the one that must never soften into a
/// prompt. `filefin_api` does not update the stored pin when this happens, and
/// no code path in this package can: a changed fingerprint on a pinned server
/// is the exact event pinning exists to make visible.
///
/// Nothing was sent — see `CertificatePinner.securityContext` for why that is
/// true even when the new certificate is one the OS would happily trust.
///
/// It also fires for an innocent cause: pinning a CA-signed server means every
/// certificate renewal changes the fingerprint. That is the price of the
/// guarantee, and the message names both values so a user can compare them.
final class CertificatePinMismatch extends FileFinApiException {
  /// [requested] presented [actual] where [expected] was pinned.
  const CertificatePinMismatch(
    this.requested, {
    required this.expected,
    required this.actual,
  });

  /// The URL that was being requested.
  final Uri requested;

  /// The fingerprint the user accepted earlier, in colon-hex.
  final String expected;

  /// The fingerprint that arrived this time, in colon-hex.
  final String actual;

  @override
  String toString() =>
      'CertificatePinMismatch: ${redactUserInfo(requested)} presented '
      '$actual, but $expected was pinned. Nothing was sent.';
}

/// A 2xx whose `Content-Type` is not `application/json` — F1's mechanism.
///
/// This server registers an SPA catch-all **outside** its route table
/// (`server.go:352`), so an unmatched `/api/*` path — a typo, a trailing
/// slash from a `Uri` join, a method mismatch, an endpoint upstream removed —
/// answers `200 text/html` with `index.html`. Verified live at v0.20.3. **No
/// path or method mismatch is ever answered with a 404 or a 405.**
///
/// So a `200` proves nothing: any SPA host, any reverse proxy with a fallback
/// and any unrelated web server answers the same way. The content type is the
/// only thing that separates them, which is why F1 is a
/// content-type-and-payload check rather than a status check, and why this
/// variant exists instead of a decode error arriving from somewhere else
/// entirely.
final class NotAFileFinServerResponse extends FileFinApiException {
  /// [requested] answered 2xx with [contentType], which is not JSON.
  const NotAFileFinServerResponse(this.requested, this.contentType);

  /// The URL that was being requested.
  final Uri requested;

  /// The `Content-Type` that arrived, or null when the response carried none.
  final String? contentType;

  @override
  String toString() =>
      'NotAFileFinServerResponse: ${redactUserInfo(requested)} answered '
      '${contentType ?? 'no content type'}, not application/json';
}

/// JSON arrived and decoded, but was not the shape the model needs.
///
/// Separate from `NotAFileFinServerResponse` because the two mean opposite
/// things: that one says "this is not the server you think it is", this one
/// says "this IS the server and it sent something we cannot read" — a version
/// skew, or a field whose type changed. §8 makes us tolerant of *added*
/// fields; it cannot make us tolerant of a `String` where an `int` belongs.
final class MalformedResponse extends FileFinApiException {
  /// [requested] answered JSON that [problem] describes the trouble with.
  const MalformedResponse(this.requested, this.problem);

  /// The URL that was being requested.
  final Uri requested;

  /// What went wrong, in the words of whatever noticed.
  final String problem;

  @override
  String toString() =>
      'MalformedResponse: ${redactUserInfo(requested)} sent JSON we could not '
      'read: $problem';
}

/// Any other non-2xx status, kept so the hierarchy stays total.
///
/// A status this package has no opinion about must still arrive as one of our
/// types. Folding it into [ConnectionFailed] would lie — the server answered,
/// it just answered something we do not model — and letting it escape as a
/// `DioException` would break the "one vocabulary" property the whole
/// hierarchy exists for.
final class ServerFailure extends FileFinApiException {
  /// [requested] answered [statusCode] with [body].
  const ServerFailure(this.statusCode, this.body, this.requested);

  /// The HTTP status the server answered with.
  final int statusCode;

  /// The response body, rendered as text for a log or a bug report.
  final String body;

  /// The URL that was being requested.
  final Uri requested;

  @override
  String toString() =>
      'ServerFailure: $statusCode from ${redactUserInfo(requested)}: $body';
}
