import 'package:dio/dio.dart';
import 'package:filefin_api/src/api_token.dart';
import 'package:filefin_api/src/auth_session.dart';
import 'package:filefin_api/src/error_mapper.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/json_response.dart';
import 'package:filefin_api/src/secret_store.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';
import 'package:filefin_core/filefin_core.dart';

/// Owns one server's personal access token: verifying, restoring, and
/// forgetting it.
///
/// **No generation counter, no in-flight-future de-duplication, no
/// rate-limit block.** None of `SessionManager`'s concurrency guards apply
/// here: there is nothing to renew, so there is nothing a second caller could
/// race a renewal for, and a wrong token is answered by the server's ordinary
/// per-account throttle rather than by anything this class needs to track.
base class TokenAuthSession extends AuthSession {
  /// Builds a manager for one server's token.
  TokenAuthSession({
    required this.authDio,
    required this.urls,
    required this.secrets,
    required this.server,
    this.pinner,
  });

  /// The `Dio` used for the one-off `GET /api/me` that proves a token works —
  /// no `TokenAuthInterceptor`, so it never attaches a header on its own; the
  /// header for the token being PROVED is passed explicitly instead.
  final Dio authDio;

  /// This server's URLs.
  final FileFinUrls urls;

  /// Where the token lives.
  final SecretStore secrets;

  /// Which saved server this is.
  final ServerId server;

  /// The pinner, so a TLS refusal during verification names the fingerprint.
  final CertificatePinner? pinner;

  ApiToken? _token;

  /// Verifies [token] against `GET /api/me` and stores it only once proven.
  ///
  /// A 401 here means the token is wrong, and is reported as [InvalidToken]
  /// rather than [SessionExpired] — there is no session to have expired, this
  /// is the same "bad credential" moment `SessionManager.login` has for a
  /// password.
  Future<AuthResult> verify(ApiToken token) async {
    final result = await _me(token);
    await secrets.write(server, SecretKind.token, token.value);
    return result;
  }

  /// Restores a stored token on a cold start, proving it still works.
  ///
  /// A dead token is deleted rather than kept: unlike a lost session cookie,
  /// there is no separate credential underneath it that might still be good —
  /// the token IS the credential, so a 401 means it, specifically, is what
  /// is wrong.
  @override
  Future<void> resume() => restore();

  /// The lower-level half of [resume], also called directly by tests that
  /// want to observe the "stored but never proven" case without a UI.
  Future<AuthResult> restore() async {
    final stored = await secrets.read(server, SecretKind.token);
    if (stored == null) throw SessionExpired(urls.me);
    try {
      return await _me(ApiToken(stored));
    } on InvalidToken {
      await secrets.delete(server, SecretKind.token);
      rethrow;
    }
  }

  Future<AuthResult> _me(ApiToken token) async {
    final url = urls.me;
    try {
      final response = await authDio.getUri<dynamic>(
        url,
        options: Options(headers: token.toHeader()),
      );
      final result = decodeModel(
        jsonObject(response, requested: url),
        AuthResult.fromJson,
        requested: url,
      );
      _token = token;
      return result;
    } on DioException catch (e) {
      final mapped = mapDioException(e, requested: url, pinner: pinner);
      throw mapped is SessionExpired ? InvalidToken(url) : mapped;
    }
  }

  /// Ends the session locally. There is no server-side revoke call from this
  /// package (§1) — that lives in FileFin's own Settings page — so this
  /// forgets the stored token and nothing else.
  @override
  Future<void> forget() async {
    await secrets.delete(server, SecretKind.token);
    _token = null;
  }

  /// The bearer header for the token already proven by [verify] or
  /// [restore], or null before either has run.
  @override
  Future<Map<String, String>?> headers() async {
    final token = _token ?? await _load();
    return token?.toHeader();
  }

  /// The synchronous twin of [headers], for `TokenAuthInterceptor`.
  ///
  /// **An interceptor's `onRequest` must call `handler.next`/`reject`
  /// unconditionally, with nothing async between it and that call** — an
  /// awaited gap there is a single statement whose removal would leave the
  /// request pipeline waiting forever, which is a hang rather than an
  /// ordinary bug (nothing can ever fail a test that never returns). This
  /// reads only the already-cached token: by the time a live client is
  /// making requests, [verify] or [restore] has already run. A never-proven
  /// token sends the request with no header, which the server 401s and
  /// `TokenAuthInterceptor.onError` turns into [InvalidToken] - a fast,
  /// honest failure instead of a silent hang.
  Map<String, String>? get headersSync => _token?.toHeader();

  Future<ApiToken?> _load() async {
    final stored = await secrets.read(server, SecretKind.token);
    if (stored == null) return null;
    return _token = ApiToken(stored);
  }

  /// Prints no token.
  @override
  String toString() => 'TokenAuthSession(${server.value}, <redacted>)';
}
