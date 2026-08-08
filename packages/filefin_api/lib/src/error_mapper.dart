import 'dart:io';

import 'package:dio/dio.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';
import 'package:filefin_api/src/tls/fingerprint.dart';
import 'package:filefin_api/src/tls/pin_decision.dart';

/// Turns dio's one exception type into our sealed hierarchy.
///
/// This lives in a **different file from `errors.dart` on purpose**:
/// `dead_types` (§5, `tool/check-constitution.sh`) asks that every sealed
/// variant be constructed outside the file that declares it, so a variant that
/// nothing can produce fails the gate rather than sitting in the tree looking
/// finished.
///
/// [requested] is passed rather than read from `error.requestOptions.uri`
/// because the caller knows the URL it *meant* to fetch, which is the one a
/// user recognises. dio's copy has been through `BaseOptions` merging and a
/// redirect, so on the 307 to HLS the two genuinely differ.
///
/// **This function never inspects a content type.** The JSON media-type check
/// belongs to 2xx responses we intend to decode and lives in
/// `json_response.dart`. Applying it here would be catastrophic in a way that
/// looks like tightening: `401 unauthorized` and `404 page not found` are
/// served as plain text (`docs/server-api.md`, "Authentication"), so a blanket
/// guard would turn every documented error into "not a FileFin server" and F3
/// would never see a 401 at all.
///
/// [pinner] is optional and is consulted only for the two exception types TLS
/// can produce. It is how a `HandshakeException` — which carries nothing but
/// an OpenSSL string — becomes a message naming the fingerprint the user has
/// to compare. Without it F15's failures would read "TLS failed", which is the
/// message F15 exists to replace.
FileFinApiException mapDioException(
  DioException error, {
  required Uri requested,
  CertificatePinner? pinner,
}) {
  final response = error.response;
  final certificate = _certificateProblem(error, requested, pinner);
  if (certificate != null) return certificate;
  return switch (error.type) {
    DioExceptionType.connectionTimeout => RequestTimedOut(
      RequestPhase.connect,
      requested,
    ),
    DioExceptionType.sendTimeout => RequestTimedOut(
      RequestPhase.send,
      requested,
    ),
    DioExceptionType.receiveTimeout => RequestTimedOut(
      RequestPhase.receive,
      requested,
    ),
    DioExceptionType.cancel => RequestCancelled(requested),
    DioExceptionType.badResponse when response != null => _fromStatus(
      response,
      requested,
    ),
    // `badResponse` with no response is not reachable through dio today, and
    // `unknown` is dio's own catch-all. Both land here rather than in a
    // `throw`: an error path that can itself throw is the one nobody tests.
    _ => ConnectionFailed(requested, cause: error.error),
  };
}

/// Turns a TLS refusal back into the decision that caused it, or null.
///
/// The two exception types are what dio produces for the two hooks, measured
/// against 5.11.0: `badCertificateCallback` returning false surfaces as a
/// `HandshakeException` under `DioExceptionType.unknown`, while
/// `validateCertificate` returning false surfaces as
/// `DioExceptionType.badCertificate`. Both are checked, so neither hook's
/// refusal can arrive as a bare "could not reach the server".
///
/// It is scoped to those two types deliberately. The pinner remembers the last
/// decision per `host:port` for as long as it lives, so consulting it on every
/// failure would let a stale rejection explain an unrelated timeout.
FileFinApiException? _certificateProblem(
  DioException error,
  Uri requested,
  CertificatePinner? pinner,
) {
  if (pinner == null) return null;
  final isTlsShaped =
      error.type == DioExceptionType.badCertificate ||
      (error.type == DioExceptionType.unknown &&
          error.error is HandshakeException);
  if (!isTlsShaped) return null;
  return switch (pinner.decisionFor(requested)) {
    RejectChanged(:final expected, :final actual) => CertificatePinMismatch(
      requested,
      expected: expected.value,
      actual: actual.value,
    ),
    RejectUntrusted(:final observed) => _notTrusted(
      requested,
      observed,
      pinner.certificateFor(requested),
    ),
    _ => null,
  };
}

/// Builds the prompt payload from the certificate the callback actually saw.
///
/// The certificate is always present alongside a `RejectUntrusted` — the same
/// call recorded both — but the field is nullable, and inventing values for a
/// null would put fabricated identity details in front of a user being asked
/// to trust something. An absent certificate degrades to empty strings and the
/// epoch, which reads as "we do not know" rather than as a claim.
FileFinApiException _notTrusted(
  Uri requested,
  CertificateFingerprint observed,
  X509Certificate? certificate,
) => CertificateNotTrusted(
  requested,
  fingerprint: observed.value,
  subject: certificate?.subject ?? '',
  issuer: certificate?.issuer ?? '',
  validTo: certificate?.endValidity ?? DateTime.fromMillisecondsSinceEpoch(0),
);

/// Maps one non-2xx status onto the variant that describes it.
FileFinApiException _fromStatus(Response<dynamic> response, Uri requested) {
  final body = '${response.data ?? ''}';
  return switch (response.statusCode) {
    401 => SessionExpired(requested),
    404 => NotFound(requested),
    429 => _rateLimited(response, requested),
    503 => CacheUnavailable(requested),
    final status => ServerFailure(status ?? 0, body, requested),
  };
}

/// Reads `Retry-After` as whole seconds, keeping the raw value when it is not.
///
/// Integer-only, deliberately. `auth.go:149` writes `int(retry.Seconds()) + 1`
/// and nothing upstream can produce an HTTP-date, so a date branch would be
/// code for a case this server cannot reach (§1). What is *not* skipped is the
/// possibility of a proxy rewriting the header: the value survives verbatim so
/// a human can see what arrived, and the parsed duration stays zero rather
/// than becoming a number nobody measured.
///
/// **The list form, not `Headers.value`.** dio's `value` *throws* when a header
/// arrived more than once, and a `429` is the worst possible moment for an
/// exception to escape the sealed hierarchy: a caller doing
/// `on FileFinApiException` gets a raw `_Exception` exactly when login is being
/// rate limited. No malice is needed — any proxy that folds or duplicates
/// `Retry-After` reaches it. Taking the first value keeps a duplicate a
/// cosmetic problem, and [RateLimited.rawRetryAfter] still shows a human what
/// arrived.
RateLimited _rateLimited(Response<dynamic> response, Uri requested) {
  final raw = response.headers['retry-after']?.firstOrNull;
  final seconds = raw == null ? null : int.tryParse(raw.trim());
  return RateLimited(
    Duration(seconds: seconds ?? 0),
    requested,
    rawRetryAfter: raw,
  );
}
