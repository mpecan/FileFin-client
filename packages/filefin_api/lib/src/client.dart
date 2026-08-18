import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:filefin_api/src/api_token.dart';
import 'package:filefin_api/src/auth_interceptor.dart';
import 'package:filefin_api/src/auth_session.dart';
import 'package:filefin_api/src/credentials.dart';
import 'package:filefin_api/src/error_mapper.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/json_response.dart';
import 'package:filefin_api/src/playback_session.dart';
import 'package:filefin_api/src/probe_result.dart';
import 'package:filefin_api/src/secret_store.dart';
import 'package:filefin_api/src/server_probe.dart';
import 'package:filefin_api/src/session.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';
import 'package:filefin_api/src/tls/fingerprint.dart';
import 'package:filefin_api/src/tls/pinned_adapter.dart';
import 'package:filefin_api/src/token_auth_interceptor.dart';
import 'package:filefin_api/src/token_auth_session.dart';
import 'package:filefin_api/src/transport.dart';
import 'package:filefin_core/filefin_core.dart';

part 'client_browse.dart';
part 'client_playback.dart';
part 'client_watch_state.dart';

/// One server's API, typed, with the 401 retry and certificate pinning already
/// wired.
///
/// **Two constructors, and the split is what makes the tests possible without
/// a test-only hook.** The primary one takes its `Dio`s, so a suite can put a
/// counting interceptor on `authDio` and assert how many logins actually
/// happened — dependency injection rather than a `@visibleForTesting` counter
/// that only exists to be looked at. [FileFinClient.forServer] is what an app
/// calls.
///
/// Every endpoint takes a `CancelToken` and every failure arrives as a
/// `FileFinApiException`; nothing here lets a `DioException` escape.
class FileFinClient {
  /// Wires [dio] with whichever interceptors [sessions]'s auth mode needs.
  ///
  /// **Interceptor order is owned here rather than by the caller**, because it
  /// is load-bearing for the password path: `CookieManager` must sit in
  /// front of `AuthInterceptor` so the replayed request picks up the
  /// `Set-Cookie` the renewal just stored. Both are inserted at positions 0
  /// and 1, so anything the caller already added runs after them. The token
  /// path needs no `CookieManager` — the server sets no cookie for a
  /// bearer-authenticated request — so only `TokenAuthInterceptor` goes on.
  ///
  /// **`LogInterceptor` is never added, here or anywhere.** dio's own prints
  /// `RequestOptions.data`, which on `/api/login` is the password.
  FileFinClient({
    required this.server,
    required Dio dio,
    required this.authDio,
    required this.jar,
    required this.sessions,
    required this.urls,
    this.pinner,
  }) : _dio = dio {
    final sessions = this.sessions;
    switch (sessions) {
      case SessionManager():
        _dio.interceptors
          ..insert(0, CookieManager(jar))
          ..insert(1, AuthInterceptor(sessions: sessions, dio: _dio));
      case TokenAuthSession():
        _dio.interceptors.insert(0, TokenAuthInterceptor(session: sessions));
      default:
        // AuthSession is a port implemented across files rather than a
        // sealed hierarchy (`SecretStore`'s reasoning applies here too), so
        // this cannot be exhaustive at compile time. Failing loudly on a
        // third implementation beats silently wiring no auth at all onto it.
        throw StateError(
          'no interceptor wiring for ${sessions.runtimeType}',
        );
    }
  }

  /// Builds a client for one saved server, with everything wired.
  ///
  /// [pin] is the fingerprint the user accepted earlier. It is resolved
  /// into memory *here* because TLS's callbacks are synchronous and cannot
  /// await a store read — so accepting a new certificate means writing the pin
  /// and building a new client, which is what keeps acceptance a deliberate
  /// act rather than something this package can do on a user's behalf.
  ///
  /// [username] comes from `settings.json`'s `servers[].lastUser`: a cold
  /// start needs it to renew a session silently, and it is not a secret.
  factory FileFinClient.forServer({
    required ServerId server,
    required Uri baseUrl,
    required SecretStore secrets,
    CertificateFingerprint? pin,
    String? username,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final urls = FileFinUrls(baseUrl);
    final jar = DefaultCookieJar();
    final pinner = CertificatePinner(pin: pin);
    // A separate adapter per Dio, from the SAME pinner. The adapter caches an
    // HttpClient and `Dio.close()` closes it, so sharing one instance would
    // let closing either client break the other. The pin state that matters
    // lives in the pinner, which is shared.
    final authDio = Dio(fileFinBaseOptions(baseUrl: baseUrl, timeout: timeout))
      ..httpClientAdapter = pinnedAdapter(pinner)
      ..interceptors.add(CookieManager(jar));
    final dio = Dio(fileFinBaseOptions(baseUrl: baseUrl, timeout: timeout))
      ..httpClientAdapter = pinnedAdapter(pinner);
    return FileFinClient(
      server: server,
      dio: dio,
      authDio: authDio,
      jar: jar,
      urls: urls,
      pinner: pinner,
      sessions: SessionManager(
        authDio: authDio,
        urls: urls,
        jar: jar,
        secrets: secrets,
        server: server,
        username: username,
        pinner: pinner,
      ),
    );
  }

  /// Builds a client for one saved server that signs in with a personal
  /// access token rather than a password.
  ///
  /// No `username` parameter: a token authenticates as whichever account
  /// minted it, and there is nothing to silently renew it with, so there is
  /// no cold-start value this factory needs ahead of a call proving the
  /// token still works.
  factory FileFinClient.forTokenServer({
    required ServerId server,
    required Uri baseUrl,
    required SecretStore secrets,
    CertificateFingerprint? pin,
    Duration timeout = const Duration(seconds: 15),
  }) {
    final urls = FileFinUrls(baseUrl);
    final jar = DefaultCookieJar();
    final pinner = CertificatePinner(pin: pin);
    final authDio = Dio(
      fileFinBaseOptions(baseUrl: baseUrl, timeout: timeout),
    )..httpClientAdapter = pinnedAdapter(pinner);
    final dio = Dio(fileFinBaseOptions(baseUrl: baseUrl, timeout: timeout))
      ..httpClientAdapter = pinnedAdapter(pinner);
    return FileFinClient(
      server: server,
      dio: dio,
      authDio: authDio,
      jar: jar,
      urls: urls,
      pinner: pinner,
      sessions: TokenAuthSession(
        authDio: authDio,
        urls: urls,
        secrets: secrets,
        server: server,
        pinner: pinner,
      ),
    );
  }

  /// Which saved server this client talks to.
  final ServerId server;

  /// The client `/api/login`, `/api/logout` and the probe use — no retry on it.
  final Dio authDio;

  /// The cookie jar both clients share, in memory only. Unused in token
  /// mode — the server sets no cookie for a bearer-authenticated request —
  /// and kept anyway so one constructor serves both modes.
  final CookieJar jar;

  /// Credential state: a password session or a token, depending on how this
  /// client was built.
  final AuthSession sessions;

  /// This server's URLs.
  final FileFinUrls urls;

  /// The pin, so a TLS refusal names the fingerprint rather than "TLS failed".
  final CertificatePinner? pinner;

  final Dio _dio;

  /// Is there a FileFin server at this address?
  ///
  /// Runs on [authDio], which carries no `AuthInterceptor`: the probe is
  /// unauthenticated and must never be able to provoke a re-auth.
  Future<ProbeResult> probeServer({CancelToken? cancelToken}) =>
      probe(dio: authDio, urls: urls, pinner: pinner, cancelToken: cancelToken);

  /// `POST /api/login` — stores the session and the password.
  ///
  /// Only meaningful on a client built by [FileFinClient.forServer]; calling
  /// it on a token-mode client is a wiring bug this names rather than
  /// silently mishandles.
  Future<AuthResult> login(Credentials credentials) {
    final sessions = this.sessions;
    if (sessions is! SessionManager) {
      throw StateError(
        'login() needs a password-mode client; this one authenticates by '
        'token',
      );
    }
    return sessions.login(credentials);
  }

  /// Verifies [token] against `GET /api/me` and stores it once proven.
  ///
  /// Only meaningful on a client built by [FileFinClient.forTokenServer];
  /// the [login] doc comment explains the symmetric guard.
  Future<AuthResult> signInWithToken(ApiToken token) {
    final sessions = this.sessions;
    if (sessions is! TokenAuthSession) {
      throw StateError(
        'signInWithToken() needs a token-mode client; this one '
        'authenticates by password',
      );
    }
    return sessions.verify(token);
  }

  /// Ends the session (password mode) or forgets the token (token mode).
  Future<void> logout() => sessions.forget();

  /// `GET /api/me` — the current user.
  Future<AuthResult> me({CancelToken? cancelToken}) => _send(
    urls.me,
    (r, url) => _one(r, url, AuthResult.fromJson),
    cancelToken: cancelToken,
  );

  /// Refuses an HTML body on a route that does not serve JSON.
  ///
  /// Same mechanism: catch-all HTML handed to an `ImageProvider`
  /// becomes a broken image with no explanation, and handed to libmpv as a
  /// subtitle becomes a track with no cues. Named here it becomes a sentence.
  static void _refuseHtml(Headers headers, Uri url) => refuseHtml(headers, url);

  /// Turns dio's exception into ours, keeping a cause we already wrapped.
  ///
  /// `AuthInterceptor` rejects with the real reason wrapped when a renewal
  /// itself fails, so a 429 arrives as `RateLimited` rather than being re-read
  /// as a plain 401 and reported as "signed out".
  FileFinApiException _asOurs(DioException error, Uri url) {
    final cause = error.error;
    if (cause is FileFinApiException) return cause;
    return mapDioException(error, requested: url, pinner: pinner);
  }

  /// Releases both clients' sockets.
  void close() {
    _dio.close();
    authDio.close();
  }

  /// Builds a URL, turning a rejected identifier into one of our errors.
  ///
  /// `ApiPaths` refuses `''`, `'.'` and `'..'` with an `ArgumentError`, and the
  /// bad value comes from **server data**, so letting it escape
  /// would mean one null id crashes the UI — the opposite of degrading visibly.
  ///
  /// What this deliberately does **not** do is filter bad items out of a list.
  /// That IS a silent failure: the list is returned exactly as
  /// decoded, and opening the bad item fails loudly, naming the value.
  Uri _uri(Uri Function() build, String field) {
    try {
      return build();
      // `avoid_catching_errors` is right almost everywhere and wrong here: the
      // rejected value came off the wire, not out of a caller's hand, so this
      // is the boundary that turns a server's bad data into one of our errors
      // rather than a raw Dart Error in front of a user.
      // ignore: avoid_catching_errors
    } on ArgumentError catch (e) {
      throw MalformedIdentifier(e.invalidValue, field);
    }
  }

  /// One GET, one decode, one error vocabulary.
  ///
  /// Every endpoint routes through here rather than carrying its own
  /// try/catch — `just dupes` (15 lines / 50 tokens / 5%) would fire on seven
  /// copies, and more importantly seven copies is seven chances to map an
  /// error slightly differently.
  Future<T> _send<T>(
    Uri url,
    T Function(Response<dynamic>, Uri) read, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.getUri<dynamic>(
        url,
        cancelToken: cancelToken,
      );
      return read(response, url);
    } on DioException catch (e) {
      throw _asOurs(e, url);
    }
  }

  /// One POST of a JSON body, one error vocabulary, no response to decode.
  ///
  /// A sibling of [_send] rather than a seventh copy of its try/catch: two
  /// copies is two chances to map an error differently.
  ///
  /// **It checks the media type even though these routes answer `204` with no
  /// body**, which is the case the check exists for rather than an oversight:
  /// an unmatched path answers `200 text/html`, and a helper reading only the
  /// status took that as a successful write, so every watch-state write
  /// reported
  /// success to a screen that had already drawn the change. A genuine `204`
  /// carries no `Content-Type` at all and passes untouched.
  Future<void> _sendJson(
    Uri url,
    Map<String, Object?> body, {
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await _dio.postUri<void>(
        url,
        data: body,
        cancelToken: cancelToken,
        options: Options(contentType: Headers.jsonContentType),
      );
      _refuseHtml(response.headers, url);
    } on DioException catch (e) {
      throw _asOurs(e, url);
    }
  }

  /// One DELETE, one error vocabulary, and no body in either direction.
  ///
  /// A sibling of [_sendJson] rather than a copy, for the same reason.
  ///
  /// It exists at all because **the verb distinguishes the two un-watch
  /// operations** (`docs/field-notes.md`): a `DELETE` carrying a body would be
  /// the other operation wearing the wrong verb. It needs its own media-type
  /// check — fixing the POST helper alone would have left the un-watch
  /// that drops the resume pointer reading the catch-all as success.
  Future<void> _sendDelete(Uri url, {CancelToken? cancelToken}) async {
    try {
      final response = await _dio.deleteUri<void>(
        url,
        cancelToken: cancelToken,
      );
      _refuseHtml(response.headers, url);
    } on DioException catch (e) {
      throw _asOurs(e, url);
    }
  }

  static T _one<T>(
    Response<dynamic> response,
    Uri url,
    T Function(Map<String, Object?>) fromJson,
  ) => decodeModel(
    jsonObject(response, requested: url),
    fromJson,
    requested: url,
  );

  static List<T> _many<T>(
    Response<dynamic> response,
    Uri url,
    T Function(Map<String, Object?>) fromJson,
  ) => [
    for (final json in jsonObjects(response, requested: url))
      decodeModel(json, fromJson, requested: url),
  ];

  @override
  String toString() => 'FileFinClient(${server.value}, ${urls.base})';
}
