import 'package:dio/dio.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/session.dart';

/// The ONLY place a `401` is interpreted (SPEC.md §5.1), so F3 exists once.
///
/// Server sessions live in memory and die with the process (L1), so a 401 on
/// any call is routine rather than exceptional. This interceptor renews the
/// session and replays the request once, transparently.
///
/// **Three separate mechanisms keep that from becoming a loop, and they guard
/// different things.**
///
/// 1. *Recursion through login is structurally impossible.* `SessionManager`
///    runs on a second `Dio` that does not carry this interceptor, so a 401
///    from `/api/login` never reaches this code. There is deliberately no "is
///    this the login path?" branch here: it would be unreachable, and §5 and
///    `dead_types` exist to stop unreachable branches being written.
/// 2. *Recursion through the retry is bounded by a marker on the request.* One
///    retry, always, whatever else happens.
/// 3. *Concurrency is handled by `SessionManager`*, which is where the state
///    is. This interceptor's job is only to stamp the generation each request
///    was issued under, so a 401 arriving after someone else has already
///    renewed can be recognised as stale.
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
