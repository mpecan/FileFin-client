import 'package:dio/dio.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/session.dart';

/// The ONLY place a `401` is interpreted (SPEC.md §5.1), so F3 exists once.
///
/// Server sessions live in memory and die with the process (L1), so a 401 on
/// any call is routine rather than exceptional. This renews the session and
/// replays the request once, transparently.
///
/// **Three separate mechanisms stop that becoming a loop and they guard
/// different things** — a second `Dio` without this interceptor, a marker on
/// the request, and `SessionManager`'s generation counter. D20 says why one
/// guard is not enough, and why there is no "is this the login path?" branch.
class AuthInterceptor extends Interceptor {
  /// Renews sessions through [sessions] and replays through [dio].
  ///
  /// [dio] is the same client this interceptor is installed on. Replaying
  /// through `dio.fetch` re-runs the whole chain — **verified, not assumed**:
  /// a counting interceptor showed `onRequest` firing twice, and the stub
  /// recorded the replayed request carrying the *new* cookie. If `fetch` ever
  /// bypassed the chain, the replay would reuse the dead cookie and 401
  /// forever, so `client_test.dart` asserts the cookie value on the wire
  /// rather than only the final status.
  AuthInterceptor({required this.sessions, required this.dio});

  /// Where the session lives.
  final SessionManager sessions;

  /// The client to replay through.
  final Dio dio;

  /// `RequestOptions.extra` key holding the generation a request was sent
  /// under.
  static const generationKey = 'filefin.sessionGeneration';

  /// `RequestOptions.extra` key marking a request as already replayed.
  static const retriedKey = 'filefin.reauthRetried';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[generationKey] = sessions.generation;
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || options.extra[retriedKey] == true) {
      return handler.next(err);
    }
    try {
      await sessions.reauthenticate(
        seenGeneration:
            options.extra[generationKey] as int? ?? sessions.generation,
      );
    } on FileFinApiException catch (e) {
      // The renewal itself failed — no stored password, or a 429. Carrying the
      // real reason out rather than letting the original 401 be re-mapped is
      // what stops a rate-limited re-auth from being reported as "signed out",
      // which would send the user to type a password into a locked account.
      return handler.reject(
        DioException(requestOptions: options, error: e, response: err.response),
      );
    }
    try {
      return handler.resolve(
        await dio.fetch<dynamic>(options..extra[retriedKey] = true),
      );
    } on DioException catch (e) {
      return handler.next(e);
    }
  }
}
