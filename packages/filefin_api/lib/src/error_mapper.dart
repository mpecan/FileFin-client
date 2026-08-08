import 'package:dio/dio.dart';
import 'package:filefin_api/src/errors.dart';

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
FileFinApiException mapDioException(
  DioException error, {
  required Uri requested,
}) {
  final response = error.response;
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
RateLimited _rateLimited(Response<dynamic> response, Uri requested) {
  final raw = response.headers.value('retry-after');
  final seconds = raw == null ? null : int.tryParse(raw.trim());
  return RateLimited(
    Duration(seconds: seconds ?? 0),
    requested,
    rawRetryAfter: raw,
  );
}
