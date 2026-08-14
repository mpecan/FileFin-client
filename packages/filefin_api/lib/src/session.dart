import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:filefin_api/src/credentials.dart';
import 'package:filefin_api/src/error_mapper.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/json_response.dart';
import 'package:filefin_api/src/secret_store.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';
import 'package:filefin_core/filefin_core.dart';

/// The session cookie's name (`auth.go`, set at `auth.go`).
const sessionCookieName = 'filefin_session';

/// Owns one server's session: logging in, restoring, and silently renewing.
///
/// **It runs on its own `Dio`.** `authDio` shares the cookie jar and the pinned
/// adapter with the main client but carries **no `AuthInterceptor`**, which is
/// what makes recursion through login structurally impossible rather than
/// merely guarded.
///
/// `now` is injected so the rate-limit block is testable without sleeping — the
/// alternative is a test that waits fifteen minutes or one that proves nothing.
class SessionManager {
  /// Builds a manager for one server.
  ///
  /// [username] is the account name a cold start already knows, from
  /// `settings.json`'s `servers[].lastUser`. It is not a secret
  /// and does not belong in the secure store, but re-authenticating needs it,
  /// so a manager constructed without one can restore a stored session and
  /// cannot silently renew it.
  SessionManager({
    required this.authDio,
    required this.urls,
    required this.jar,
    required this.secrets,
    required this.server,
    String? username,
    this.pinner,
    DateTime Function() now = DateTime.now,
  }) : _username = username,
       _now = now;

  /// The `Dio` used for `/api/login`, `/api/logout` and `/api/me`.
  final Dio authDio;

  /// This server's URLs.
  final FileFinUrls urls;

  /// The jar shared with the main client, so a fresh cookie reaches its
  /// requests without anything copying it across.
  final CookieJar jar;

  /// Where the password and session live.
  final SecretStore secrets;

  /// Which saved server this is.
  final ServerId server;

  /// The pinner, so a TLS refusal during login names the fingerprint.
  final CertificatePinner? pinner;

  final DateTime Function() _now;

  String? _username;
  int _generation = 0;
  DateTime? _blockedUntil;
  String? _rawRetryAfter;
  Future<void>? _inFlight;
  bool _passwordRejected = false;

  /// Increments on every successful login.
  ///
  /// Half of the concurrency guard: a request stamps the generation it was
  /// issued under, and a 401 arriving after someone else has already logged in
  /// carries a stale one and is answered without a second login. With a
  /// five-failure account limiter in front of `/api/login`, a pointless extra
  /// attempt is not cosmetic.
  int get generation => _generation;

  /// Logs in and stores both the password and the session.
  ///
  /// A `401` here is **bad credentials, not a session loss** — this is the one
  /// route where that is true, and it is why the mapping is done here rather
  /// than in `mapDioException`, which has no way to know which route it is
  /// looking at.
  Future<AuthResult> login(Credentials credentials) async {
    _refuseWhileBlocked();
    // A caller-driven login is the new password [_refuseWhileRejected] is
    // waiting for, so it always gets its one attempt. `_renew` never reaches
    // here while the latch is set, so this cannot clear a latch it just wrote.
    _passwordRejected = false;
    final url = urls.login;
    final AuthResult result;
    try {
      final response = await authDio.postUri<dynamic>(
        url,
        data: credentials.toJson(),
      );
      result = decodeModel(
        jsonObject(response, requested: url),
        AuthResult.fromJson,
        requested: url,
      );
    } on DioException catch (e) {
      throw _loginFailure(e, url);
    }
    final session = await sessionCookie();
    if (session == null) {
      // Storing the password against a session that does not exist would make
      // every later call 401 into a re-auth that logs in and stores nothing
      // again — a loop that looks like a server fault.
      throw MalformedResponse(
        url,
        'the login succeeded but set no $sessionCookieName cookie',
      );
    }
    await secrets.write(server, SecretKind.password, credentials.password);
    await secrets.write(server, SecretKind.session, session);
    _username = credentials.username;
    _blockedUntil = null;
    _generation++;
    return result;
  }

  /// Validates a stored session without sending a password.
  ///
  /// Seeds the jar from the secure store and asks `GET /api/me`. A 401 here is
  /// the ordinary a lost session path — the server restarted and forgot the
  /// session — and arrives as `SessionExpired` for the caller to answer with
  /// [login] or [reauthenticate].
  Future<AuthResult> restore() async {
    final stored = await secrets.read(server, SecretKind.session);
    if (stored == null) throw SessionExpired(urls.me);
    await jar.saveFromResponse(urls.base, [
      Cookie(sessionCookieName, stored)..path = '/',
    ]);
    final url = urls.me;
    try {
      final response = await authDio.getUri<dynamic>(url);
      return decodeModel(
        jsonObject(response, requested: url),
        AuthResult.fromJson,
        requested: url,
      );
    } on DioException catch (e) {
      final mapped = mapDioException(e, requested: url, pinner: pinner);
      if (mapped is SessionExpired) {
        // The server has told us this cookie is dead, so keeping it is keeping
        // a value that can only ever be wrong (our own format, so no
        // migration, no fallback). It also stops `restore()` from looking
        // recoverable on the next cold start — without this, an app that
        // retried `restore()` would re-seed the jar with the same dead cookie
        // forever. The PASSWORD stays: silent renewal is what it is for,
        // and this is the moment it is needed.
        await secrets.delete(server, SecretKind.session);
        await jar.delete(urls.base);
      }
      throw mapped;
    }
  }

  /// Renews the session silently, at most once per generation.
  ///
  /// [seenGeneration] is what the failing request was stamped with. **Two
  /// guards, both needed**, answering different questions: the generation
  /// returns immediately when someone else already logged in since this request
  /// was issued (the shape after a restart 401s everything at once), while the
  /// in-flight future makes N callers that *do* need a login share one rather
  /// than race a five-failure limiter. Without the future the concurrent count
  /// is 2..9; without the generation it is 9.
  Future<void> reauthenticate({required int seenGeneration}) {
    if (_generation != seenGeneration) return Future<void>.value();
    return _inFlight ??= _renew().whenComplete(() => _inFlight = null);
  }

  /// Ends the session server-side and forgets this account's secrets.
  ///
  /// The certificate pin is deliberately kept: it is about the *server's*
  /// identity rather than the user's, and clearing it would re-prompt for
  /// trust-on-first-use on every sign-out — which trains a user to click
  /// through the one dialog that exists for it.
  /// It refuses an HTML body for the reason the watch-state writes do: this
  /// route reads nothing, so without the check a `POST` that reached the SPA
  /// catch-all instead of the handler would report a server session ended that
  /// is still alive. The local half below happens either way.
  Future<void> logout() async {
    final url = urls.logout;
    try {
      refuseHtml((await authDio.postUri<dynamic>(url)).headers, url);
    } on DioException catch (e) {
      throw mapDioException(e, requested: url, pinner: pinner);
    } finally {
      // Local sign-out happens whether or not the server answered. Someone who
      // taps "sign out" while the server is down must still end up signed out;
      // keeping the password because a request failed would mean the app
      // silently signs itself back in at the next 401.
      //
      // `auth.go` writes Go's `MaxAge: -1`, which reaches the wire as
      // `Max-Age=0`, and cookie_jar 4.0.9 does honour that — measured, not
      // assumed. This clears the jar anyway, because the failure path above
      // never receives that header at all.
      await jar.delete(urls.base);
      await secrets.delete(server, SecretKind.session);
      await secrets.delete(server, SecretKind.password);
      _username = null;
      _blockedUntil = null;
      _passwordRejected = false;
    }
  }

  Future<void> _renew() async {
    _refuseWhileBlocked();
    _refuseWhileRejected();
    final username = _username;
    final password = await secrets.read(server, SecretKind.password);
    if (username == null || password == null) {
      // the silent-renewal promise is silent re-auth; without the password
      // there is nothing silent to do, and guessing is not an option. The
      // caller prompts.
      throw SessionExpired(urls.login);
    }
    await login(Credentials(username: username, password: password));
  }

  /// Throws without touching the network while a 429 block is in force.
  void _refuseWhileBlocked() {
    final until = _blockedUntil;
    if (until == null) return;
    final remaining = until.difference(_now());
    if (remaining.isNegative || remaining == Duration.zero) return;
    throw RateLimited(remaining, urls.login, rawRetryAfter: _rawRetryAfter);
  }

  /// Throws without touching the network once the stored password is known bad.
  ///
  /// **The generation guard and the in-flight future bound concurrency;
  /// nothing bounded repetition.** The server locks an account after five
  /// failures in fifteen minutes, and without this
  /// latch ten sequential calls sent ten logins and locked it — measured.
  /// The benign cause is a password changed server-side while this client still
  /// holds the old one.
  ///
  /// Cleared by a caller supplying credentials, and by [logout]. No timer:
  /// unlike a 429, nothing about waiting makes a wrong password right.
  void _refuseWhileRejected() {
    if (_passwordRejected) throw InvalidCredentials(urls.login);
  }

  FileFinApiException _loginFailure(DioException error, Uri url) {
    final mapped = mapDioException(error, requested: url, pinner: pinner);
    if (mapped is SessionExpired) {
      _passwordRejected = true;
      return InvalidCredentials(url);
    }
    if (mapped is RateLimited) {
      _blockedUntil = _now().add(mapped.retryAfter);
      _rawRetryAfter = mapped.rawRetryAfter;
    }
    return mapped;
  }

  /// The live session cookie's value, or null when the jar holds none.
  ///
  /// **Public because playback needs the value itself, not just its effect.**
  /// Everything else in this package sends the cookie by having dio's
  /// `CookieManager` attach it; libmpv opens its own socket from native code
  /// and has to be handed the header, so this is the one place the value
  /// leaves the jar. It is read out immediately before an open and never
  /// stored anywhere by the caller — `PlaybackSessionHeaders` is what carries
  /// it from here, and it redacts.
  Future<String?> sessionCookie() async {
    final cookies = await jar.loadForRequest(urls.base);
    for (final cookie in cookies) {
      if (cookie.name == sessionCookieName) return cookie.value;
    }
    return null;
  }

  /// Prints no password, no session value and no username.
  ///
  /// `secret_tostring` flags this class because its name matches `Session`,
  /// and an explicit non-leaking override is the right answer to that rather
  /// than a rename: it genuinely holds a session, and a future field on it
  /// would be exactly the kind that must not print.
  @override
  String toString() =>
      'SessionManager(${server.value}, generation $_generation, <redacted>)';
}
