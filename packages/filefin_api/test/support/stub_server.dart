import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A **stub transport**, not a mock — and the difference is the point.
///
/// It is a real `HttpServer` on `127.0.0.1:0`, so every test that uses it goes
/// through real sockets, real dio, a real cookie jar and real headers. What a
/// mocked `HttpClientAdapter` would let us skip is exactly the layer F3 and
/// F15 live in: interceptor ordering, `Set-Cookie` round-tripping, and whether
/// a retried request carries the *new* cookie.
///
/// **What it cannot prove is that FileFin returns these bytes.** That is what
/// `test/fixtures/` (captured from a real server, §8) and `just it` (a real
/// `filefin` binary) are for. A stub proves our side of the conversation; it
/// is not evidence about the server's side, and a test that only ever talks to
/// this file is a test about our own opinions.
///
/// Its default responder is the **SPA catch-all**: `200 text/html` with an
/// `index.html` body, which is what the real server answers for any path it
/// does not route (`server.go:352`, verified live at v0.20.3). So a test that
/// addresses a path nothing registered fails the way production would — with a
/// success that is not one — rather than with a 404 the real server never
/// sends.
class StubServer {
  StubServer._(this._server);

  final HttpServer _server;
  final Map<String, StubResponder> _routes = {};

  /// Every request the server received, in order, with headers and body.
  final List<StubRequest> requests = [];

  /// Binds an ephemeral loopback port and starts serving.
  static Future<StubServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = StubServer._(server);
    unawaited(server.forEach(stub._handle));
    return stub;
  }

  /// The base URL a `FileFinUrls` should be built from.
  Uri get baseUrl => Uri.parse('http://127.0.0.1:${_server.port}');

  /// How many requests arrived for [path].
  int countFor(String path) => requests.where((r) => r.path == path).length;

  /// Registers [responder] for [path]. Later registrations replace earlier.
  ///
  /// [path] comes from `FileFinUrls(...).state.path`, never a string literal,
  /// so renaming a route in `ApiPaths` cannot leave a stub silently answering
  /// the old one.
  void on(String path, StubResponder responder) => _routes[path] = responder;

  /// Stops serving and drops every connection.
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final headers = <String, String>{};
    request.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(', '));
    final recorded = StubRequest(
      method: request.method,
      path: request.uri.path,
      query: request.uri.queryParameters,
      headers: headers,
      body: body,
    );
    requests.add(recorded);

    final responder = _routes[recorded.path] ?? _spaCatchAll;
    final reply = responder(recorded);
    if (reply == null) {
      // A responder returning null never answers at all, which is how the
      // receive-timeout case is exercised without a `sleep` a slow machine
      // could turn into a flake.
      return;
    }
    request.response.statusCode = reply.status;
    request.response.headers.set(
      HttpHeaders.contentTypeHeader,
      reply.contentType,
    );
    reply.headers.forEach(request.response.headers.set);
    request.response.write(reply.body);
    await request.response.close();
  }

  static StubResponse _spaCatchAll(StubRequest request) => const StubResponse(
    status: 200,
    body: '<!doctype html><html><body>FileFin</body></html>',
    contentType: 'text/html; charset=utf-8',
  );
}

/// One request as the server saw it.
class StubRequest {
  /// Records a request's method, path, query, headers and body.
  const StubRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.headers,
    required this.body,
  });

  /// The HTTP method.
  final String method;

  /// The path, without query string.
  final String path;

  /// The decoded query parameters.
  final Map<String, String> query;

  /// Every header, lower-cased, values joined with `, `.
  final Map<String, String> headers;

  /// The request body as UTF-8 text.
  final String body;

  /// The `Cookie` header, or `null` when the request carried none.
  String? get cookie => headers['cookie'];

  @override
  String toString() => '$method $path cookie=${cookie ?? '<none>'}';
}

/// One canned response.
class StubResponse {
  /// A response with an explicit status, body and content type.
  const StubResponse({
    required this.status,
    required this.body,
    required this.contentType,
    this.headers = const {},
  });

  /// `200 application/json` carrying [value] encoded.
  StubResponse.json(Object? value, {this.status = 200, this.headers = const {}})
    : body = jsonEncode(value),
      contentType = 'application/json; charset=utf-8';

  /// The plain-text `401 unauthorized` the auth middleware writes
  /// (`auth.go:79-93`) — **not** JSON, which is the whole trap.
  const StubResponse.unauthorized()
    : status = 401,
      body = 'unauthorized',
      contentType = 'text/plain; charset=utf-8',
      headers = const {};

  /// The status line.
  final int status;

  /// The body, written as UTF-8.
  final String body;

  /// The `Content-Type` header.
  final String contentType;

  /// Any additional headers, such as `Set-Cookie` or `Retry-After`.
  final Map<String, String> headers;
}

/// Answers one request, or returns `null` to never answer at all.
///
/// The `null` arm is how a receive timeout is exercised without a `sleep` that
/// a slow machine could turn into a flake.
typedef StubResponder = StubResponse? Function(StubRequest request);
