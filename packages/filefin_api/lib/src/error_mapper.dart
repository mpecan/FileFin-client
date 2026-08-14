import 'dart:io';

import 'package:dio/dio.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';
import 'package:filefin_api/src/tls/fingerprint.dart';
import 'package:filefin_api/src/tls/pin_decision.dart';

/// Turns dio's one exception type into our sealed hierarchy.
///
/// In a **different file from `errors.dart` on purpose**: `dead_types`
/// wants every sealed variant constructed outside its declaring file.
///
/// [requested] is passed rather than read from `error.requestOptions.uri`,
/// because the caller knows the URL it *meant* to fetch — dio's copy has been
/// through `BaseOptions` merging, and on the 307 the two genuinely differ.
///
/// **This never inspects a content type**. [pinner] is consulted only for
/// the two exception types TLS can produce, and is what turns a
/// `HandshakeException` into a message naming the fingerprint to compare.
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
    400 => BadRequest(requested, body),
    401 => SessionExpired(requested),
    404 => NotFound(requested),
    // It is the file route's 415 rather than the HLS route's: this
    // client never requests `.../hls/index.m3u8` itself (`errors_playback.dart`
    // says why), so `transcoding disabled` is the only shape that reaches here.
    //
    // **Scoped to that route, because the sentence names a file.** Mapped
    // globally it told the LOGIN and DETAIL screens "This file needs
    // transcoding": `filefin` itself answers 415 nowhere else, but a reverse
    // proxy in front of it answers one for a content type it dislikes on any
    // route at all, and self-hosters put reverse proxies in front of things.
    // Off the file route a 415 is a status we have no reading of, which is
    // what `ServerFailure` is for.
    415 when _isFileRoute(requested) => TranscodingDisabled(requested),
    429 => _rateLimited(response, requested),
    503 => CacheUnavailable(requested),
    final status => ServerFailure(status ?? 0, body, requested),
  };
}

/// Whether [url] is the media FILE route — the one route whose 415
/// gives a meaning.
///
/// Matched on the LAST segments rather than on the whole path, so a FileFin
/// mounted under a reverse proxy's path prefix still matches — which matters,
/// because a proxy is exactly what produces the 415s this predicate exists to
/// keep out. The two routes that extend this one, `.../hls/...` and
/// `.../sub/{k}`, end elsewhere and do not match.
///
/// Segment comparison rather than a regular expression, because a pattern
/// spelling the path out is indistinguishable from an endpoint to
/// `just constitution`'s `undocumented_endpoint` scan.
bool _isFileRoute(Uri url) {
  final parts = url.pathSegments;
  return parts.length >= 5 &&
      parts[parts.length - 2] == 'file' &&
      parts[parts.length - 4] == 'media' &&
      parts[parts.length - 5] == 'api';
}

/// Reads `Retry-After` as whole seconds, keeping the raw value when it is not.
///
/// Integer-only, deliberately: `auth.go` writes `int(retry.Seconds) + 1`
/// and nothing upstream can produce an HTTP-date, so a date branch would be
/// code for a case this server cannot reach. A proxy rewriting the header
/// is *not* dismissed — the value survives verbatim in
/// [RateLimited.rawRetryAfter] and the parsed duration stays zero rather than
/// becoming a number nobody measured.
///
/// **The list form, not `Headers.value`**, which throws on a repeated header
/// (`docs/field-notes.md`) — and a `429` is the worst moment for an exception
/// to escape the sealed hierarchy.
RateLimited _rateLimited(Response<dynamic> response, Uri requested) {
  final raw = response.headers['retry-after']?.firstOrNull;
  final seconds = raw == null ? null : int.tryParse(raw.trim());
  return RateLimited(
    Duration(seconds: seconds ?? 0),
    requested,
    rawRetryAfter: raw,
  );
}
