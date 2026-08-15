import 'package:dio/dio.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/token_auth_session.dart';

/// The token equivalent of `AuthInterceptor`: no renewal to guard, so one
/// method rather than three, with no generation, no in-flight future, and
/// no replay.
///
/// **A separate file, not a second class in `auth_interceptor.dart`** -
/// `mutation_test` mutates a changed file whole, and appending here would
/// drag the untouched `AuthInterceptor` into every run this package does.
///
/// Attaches the bearer header on every request; a `401` maps straight to
/// [InvalidToken], since nothing here can tell a wrong token from a revoked
/// one and neither is worth a second request.
class TokenAuthInterceptor extends Interceptor {
  /// Reads the header to attach from [session].
  TokenAuthInterceptor({required this.session});

  /// Where the token lives.
  final TokenAuthSession session;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final headers = session.headersSync;
    if (headers != null) options.headers.addAll(headers);
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: InvalidToken(err.requestOptions.uri),
        response: err.response,
      ),
    );
  }

  /// Prints no token.
  @override
  String toString() => 'TokenAuthInterceptor(<redacted>)';
}
