import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:filefin_api/src/auth_interceptor.dart';
import 'package:filefin_api/src/credentials.dart';
import 'package:filefin_api/src/error_mapper.dart';
import 'package:filefin_api/src/errors.dart';
import 'package:filefin_api/src/json_response.dart';
import 'package:filefin_api/src/probe_result.dart';
import 'package:filefin_api/src/secret_store.dart';
import 'package:filefin_api/src/server_probe.dart';
import 'package:filefin_api/src/session.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';
import 'package:filefin_api/src/tls/fingerprint.dart';
import 'package:filefin_api/src/tls/pinned_adapter.dart';
import 'package:filefin_api/src/transport.dart';
import 'package:filefin_core/filefin_core.dart';

/// One server's API, typed, with F3's retry and F15's pinning already wired.
///
/// **Two constructors, and the split is what makes the tests possible without
/// a test-only hook.** The primary one takes its `Dio`s, so a suite can put a
/// counting interceptor on `authDio` and assert how many logins actually
/// happened — dependency injection rather than a `@visibleForTesting` counter
/// that only exists to be looked at. [FileFinClient.forServer] is what an app
/// calls.
///
/// Every endpoint takes a `CancelToken` (NF5) and every failure arrives as a
/// `FileFinApiException`; nothing here lets a `DioException` escape.
class FileFinClient {
  /// Wires [dio] with the cookie jar and F3, in that order.
  ///
  /// **Interceptor order is owned here rather than by the caller**, because it
  /// is load-bearing: `CookieManager` must sit in front of `AuthInterceptor`
  /// so the replayed request picks up the `Set-Cookie` the renewal just
  /// stored. They are inserted at positions 0 and 1, so anything the caller
  /// already added runs after them.
  ///
  /// **`LogInterceptor` is never added, here or anywhere.** dio's own prints
  /// `RequestOptions.data`, which on `/api/login` is the password (§9, NF4).
  FileFinClient({
    required this.server,
    required Dio dio,
    required this.authDio,
    required this.jar,
    required this.sessions,
    required this.urls,
    this.pinner,
  }) : _dio = dio {
    _dio.interceptors
      ..insert(0, CookieManager(jar))
      ..insert(1, AuthInterceptor(sessions: sessions, dio: _dio));
  }

  /// Builds a client for one saved server, with everything wired.
  ///
  /// [pin] is the fingerprint the user accepted earlier (F15). It is resolved
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

  /// Which saved server this client talks to.
  final ServerId server;

  /// The client `/api/login`, `/api/logout` and the probe use — no F3 on it.
  final Dio authDio;

  /// The cookie jar both clients share, in memory only (§9).
  final CookieJar jar;

  /// Session state and renewal.
  final SessionManager sessions;

  /// This server's URLs.
  final FileFinUrls urls;

  /// The pin, so a TLS refusal names the fingerprint rather than "TLS failed".
  final CertificatePinner? pinner;

  final Dio _dio;

  /// Is there a FileFin server at this address (F1)?
  ///
  /// Runs on [authDio], which carries no `AuthInterceptor`: the probe is
  /// unauthenticated and must never be able to provoke a re-auth.
  Future<ProbeResult> probeServer({CancelToken? cancelToken}) =>
      probe(dio: authDio, urls: urls, cancelToken: cancelToken);

  /// `POST /api/login` — stores the session and the password (F2).
  Future<AuthResult> login(Credentials credentials) =>
      sessions.login(credentials);

  /// `POST /api/logout` — ends the session and forgets this account.
  Future<void> logout() => sessions.logout();

  /// `GET /api/me` — the current user.
  Future<AuthResult> me({CancelToken? cancelToken}) => _send(
    urls.me,
    (r, url) => _one(r, url, AuthResult.fromJson),
    cancelToken: cancelToken,
  );

  /// `GET /api/categories` — the flat list; the tree is assembled client-side.
  Future<List<Category>> categories({CancelToken? cancelToken}) => _send(
    urls.categories,
    (r, url) => _many(r, url, Category.fromJson),
    cancelToken: cancelToken,
  );

  /// `GET /api/category/{id}/media` — direct children, not the subtree.
  ///
  /// `async` rather than a plain arrow so that a rejected identifier arrives
  /// as a **failed Future** and not as a synchronous throw. `_uri` runs before
  /// the first await, and a caller awaiting this method should never have to
  /// wrap the call site in a try as well.
  Future<List<MediaSummary>> categoryMedia(
    CategoryId id, {
    CancelToken? cancelToken,
  }) async => _send(
    _uri(() => urls.categoryMedia(id), 'category id'),
    (r, url) => _many(r, url, MediaSummary.fromJson),
    cancelToken: cancelToken,
  );

  /// `GET /api/media/{id}` — the full detail payload.
  ///
  /// `async` for the same reason as [categoryMedia].
  Future<MediaDetail> mediaDetail(
    MediaId id, {
    CancelToken? cancelToken,
  }) async => _send(
    _uri(() => urls.mediaDetail(id), 'media id'),
    (r, url) => _one(r, url, MediaDetail.fromJson),
    cancelToken: cancelToken,
  );

  /// `GET /api/media/{id}/poster` — image bytes, or **null when there is no
  /// poster**.
  ///
  /// **`null` is a 404 and a 404 is normal here.** `docs/server-api.md` records
  /// it: an un-enriched library has no artwork, and the server answers that
  /// with a 404 rather than an empty body. Surfacing it as an error would put a
  /// failure in front of every tile of a freshly imported library. Every OTHER
  /// failure stays in the sealed hierarchy — a 503 is still `CacheUnavailable`,
  /// so "the server is rebuilding" never reads as "you have no artwork".
  ///
  /// [size] is a hint and not a contract (`media.go:351`): the server serves
  /// the pre-built variant **if it exists** and silently falls back otherwise,
  /// so the returned image may be any dimensions. It is only put on the wire
  /// when asked for, because an absent value and an unrecognised one behave
  /// identically and sending one always would make every request look like a
  /// request for a variant.
  ///
  /// `async` for the same reason as [categoryMedia]: a rejected identifier
  /// arrives as a failed Future. A grid building 5000 tiles must not have to
  /// wrap the call in a `try` as well as an `await`.
  Future<Uint8List?> posterBytes(
    MediaId id, {
    PosterSize? size,
    CancelToken? cancelToken,
  }) async {
    final url = _uri(() => urls.poster(id, size: size), 'media id');
    try {
      final response = await _dio.getUri<List<int>>(
        url,
        cancelToken: cancelToken,
        // NOT `_send`. That path decodes JSON, and a poster is bytes; running
        // an image through `jsonDecode` would report a broken server for a
        // working one. `ResponseType.bytes` also stops dio deciding for itself
        // what to do with the body based on the content type.
        options: Options(responseType: ResponseType.bytes),
      );
      _refuseSpaCatchAll(response, url);
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      final cause = e.error;
      if (cause is FileFinApiException) throw cause;
      final mapped = mapDioException(e, requested: url, pinner: pinner);
      if (mapped is NotFound) return null;
      throw mapped;
    }
  }

  /// Refuses an HTML body on a route that serves bytes.
  ///
  /// Same reasoning as F1, and the same mechanism: this server registers its
  /// SPA catch-all outside the route table (`server.go:352`), so a route that
  /// moved — or an address that is not FileFin at all — answers `200
  /// text/html` with `index.html`. Those bytes handed to an `ImageProvider`
  /// become a broken image with no explanation; named here they become a
  /// sentence.
  ///
  /// Anything else is allowed through on purpose. The server serves the poster
  /// with `http.ServeFile`, so the content type is whatever the file is — WebP,
  /// PNG, or absent — and a client insisting on `image/*` would refuse posters
  /// that work.
  static void _refuseSpaCatchAll(Response<List<int>> response, Uri url) {
    final contentType =
        response.headers[Headers.contentTypeHeader]?.firstOrNull;
    if (contentType != null &&
        contentType.split(';').first.trim().toLowerCase() == 'text/html') {
      throw NotAFileFinServerResponse(url, contentType);
    }
  }

  /// Releases both clients' sockets.
  void close() {
    _dio.close();
    authDio.close();
  }

  /// Builds a URL, turning a rejected identifier into one of our errors.
  ///
  /// `ApiPaths` refuses `''`, `'.'` and `'..'` with an `ArgumentError`, because
  /// `Uri` deletes those segments and the request would silently address a
  /// **shorter route** that the SPA catch-all answers `200 text/html`.
  ///
  /// The bad value comes from **server data** — `MediaSummary.id` and
  /// `MediaDetail.id` both default to `MediaId('')`, so a payload with a
  /// missing `id` produces one. Letting `ArgumentError` escape means one null
  /// id crashes the UI, which is the opposite of G5's "degrade visibly rather
  /// than silently".
  ///
  /// What this deliberately does **not** do is filter bad items out of a list.
  /// That IS the silent failure G5 forbids: the list is returned exactly as
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
      // `AuthInterceptor` rejects with the real reason wrapped when a renewal
      // itself fails, so a 429 arrives as `RateLimited` rather than being
      // re-read as a plain 401 and reported as "signed out".
      final cause = e.error;
      if (cause is FileFinApiException) throw cause;
      throw mapDioException(e, requested: url, pinner: pinner);
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
