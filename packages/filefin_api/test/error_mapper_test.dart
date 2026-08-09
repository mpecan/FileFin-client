import 'package:dio/dio.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:test/test.dart';

/// The URL every case below claims to have been requesting.
final Uri requested = Uri.parse('https://filefin.example/api/me');

RequestOptions get _opts => RequestOptions(path: '/api/me');

/// A `DioException` of [type] carrying no response — the transport cases.
DioException transport(DioExceptionType type, {Object? error}) =>
    DioException(requestOptions: _opts, type: type, error: error);

/// A `DioException` the way dio itself builds one for a non-2xx status.
DioException badResponse(
  int status,
  Object? body, {
  String contentType = 'text/plain; charset=utf-8',
  Map<String, List<String>>? extraHeaders,
}) => DioException(
  requestOptions: _opts,
  type: DioExceptionType.badResponse,
  response: Response<Object?>(
    requestOptions: _opts,
    statusCode: status,
    data: body,
    headers: Headers.fromMap({
      'content-type': [contentType],
      ...?extraHeaders,
    }),
  ),
);

void main() {
  group('transport failures', () {
    test('each timeout names the phase it happened in (NF5)', () {
      expect(
        mapDioException(
          transport(DioExceptionType.connectionTimeout),
          requested: requested,
        ),
        isA<RequestTimedOut>().having(
          (e) => e.phase,
          'phase',
          RequestPhase.connect,
        ),
      );
      expect(
        mapDioException(
          transport(DioExceptionType.sendTimeout),
          requested: requested,
        ),
        isA<RequestTimedOut>().having(
          (e) => e.phase,
          'phase',
          RequestPhase.send,
        ),
      );
      expect(
        mapDioException(
          transport(DioExceptionType.receiveTimeout),
          requested: requested,
        ),
        isA<RequestTimedOut>().having(
          (e) => e.phase,
          'phase',
          RequestPhase.receive,
        ),
      );
    });

    test('cancellation is its own outcome, not a failure (NF5)', () {
      expect(
        mapDioException(
          transport(DioExceptionType.cancel),
          requested: requested,
        ),
        isA<RequestCancelled>(),
      );
    });

    test('a refused connection keeps the cause for the UI to show', () {
      const cause = SocketishCause('Connection refused');
      final mapped = mapDioException(
        transport(DioExceptionType.connectionError, error: cause),
        requested: requested,
      );
      expect(mapped, isA<ConnectionFailed>());
      expect((mapped as ConnectionFailed).cause, cause);
    });

    test('an unclassified DioException still lands somewhere typed', () {
      // The hierarchy has to be TOTAL: `mapDioException` is the only path
      // from dio into our error types, so a type it does not recognise must
      // not escape as a raw DioException. dio adds exception types between
      // minor versions, and the pin is what makes that a review event rather
      // than a crash.
      expect(
        mapDioException(
          transport(DioExceptionType.unknown, error: 'something odd'),
          requested: requested,
        ),
        isA<ConnectionFailed>(),
      );
    });
  });

  group('status codes', () {
    test('401 is a session loss, and its plain-text body is not a defect', () {
      // THE TRAP THIS TEST EXISTS FOR. The server answers 401 with the
      // plain-text body `unauthorized`, not JSON (docs/server-api.md,
      // "Authentication"). A JSON content-type guard applied to every
      // response — rather than only to a 2xx we intend to decode — would turn
      // this into "not a FileFin server" and F3 would never see a 401 at all.
      final mapped = mapDioException(
        badResponse(401, 'unauthorized'),
        requested: requested,
      );
      expect(mapped, isA<SessionExpired>());
      expect(mapped, isNot(isA<ServerFailure>()));
    });

    test('404 is not found, and its body is the other plain text', () {
      expect(
        mapDioException(
          badResponse(404, '404 page not found'),
          requested: requested,
        ),
        isA<NotFound>(),
      );
      expect(
        mapDioException(badResponse(404, 'not found'), requested: requested),
        isA<NotFound>(),
      );
    });

    test('503 is the cache being unavailable, which is recoverable', () {
      expect(
        mapDioException(
          badResponse(503, 'cache unavailable'),
          requested: requested,
        ),
        isA<CacheUnavailable>(),
      );
    });

    test('429 carries Retry-After as whole seconds (auth.go:149)', () {
      final mapped = mapDioException(
        badResponse(
          429,
          'too many requests',
          extraHeaders: {
            'retry-after': ['900'],
          },
        ),
        requested: requested,
      );
      expect(mapped, isA<RateLimited>());
      expect((mapped as RateLimited).retryAfter, const Duration(seconds: 900));
      expect(mapped.rawRetryAfter, '900');
    });

    test('a 429 with no Retry-After does not invent a delay', () {
      final mapped =
          mapDioException(
                badResponse(429, 'too many requests'),
                requested: requested,
              )
              as RateLimited;
      expect(mapped.retryAfter, Duration.zero);
      expect(mapped.rawRetryAfter, isNull);
    });

    test('an HTTP-date Retry-After is kept raw rather than guessed at', () {
      // This server sends whole seconds and nothing else (`auth.go:149` is
      // `int(retry.Seconds()) + 1`), so there is no HTTP-date branch to write
      // — §1. What there IS is a refusal to fabricate a number from a value
      // we did not parse: the raw header survives for a human to read.
      final mapped =
          mapDioException(
                badResponse(
                  429,
                  'too many requests',
                  extraHeaders: {
                    'retry-after': ['Wed, 21 Oct 2026 07:28:00 GMT'],
                  },
                ),
                requested: requested,
              )
              as RateLimited;
      expect(mapped.retryAfter, Duration.zero);
      expect(mapped.rawRetryAfter, 'Wed, 21 Oct 2026 07:28:00 GMT');
    });

    test('anything unmapped keeps the hierarchy total', () {
      final mapped =
          mapDioException(
                badResponse(500, 'internal error'),
                requested: requested,
              )
              as ServerFailure;
      expect(mapped.statusCode, 500);
      expect(mapped.body, 'internal error');
    });

    test('a badResponse with no response at all is still typed', () {
      expect(
        mapDioException(
          transport(DioExceptionType.badResponse),
          requested: requested,
        ),
        isA<ConnectionFailed>(),
      );
    });
  });

  group('what a message may say', () {
    test('every variant names the URL it was requesting', () {
      final all = <FileFinApiException>[
        mapDioException(
          transport(DioExceptionType.connectionTimeout),
          requested: requested,
        ),
        mapDioException(
          transport(DioExceptionType.cancel),
          requested: requested,
        ),
        mapDioException(
          transport(DioExceptionType.connectionError),
          requested: requested,
        ),
        mapDioException(badResponse(401, 'unauthorized'), requested: requested),
        mapDioException(badResponse(404, 'x'), requested: requested),
        mapDioException(badResponse(503, 'x'), requested: requested),
        mapDioException(badResponse(415, 'x'), requested: requested),
        mapDioException(badResponse(429, 'x'), requested: requested),
        mapDioException(badResponse(500, 'x'), requested: requested),
      ];
      for (final e in all) {
        expect(
          e.toString(),
          contains('filefin.example'),
          reason: '${e.runtimeType} does not say where it happened',
        );
      }
    });

    test('each message is asserted verbatim, because prose is source', () {
      // The same reasoning `filefin_core` reached for `RangeError`'s bounds
      // (STATE.md, M1.10): a message is mutable source that nothing else in
      // the suite reads, so an assertion of "contains the host" leaves every
      // word of it undefended. These are what a user and a log reader see, so
      // they are pinned exactly.
      const url = 'https://filefin.example/api/me';
      expect(
        RequestTimedOut(RequestPhase.connect, requested).toString(),
        'RequestTimedOut: timed out connecting $url',
      );
      expect(
        RequestTimedOut(RequestPhase.send, requested).toString(),
        'RequestTimedOut: timed out sending the request $url',
      );
      expect(
        RequestTimedOut(RequestPhase.receive, requested).toString(),
        'RequestTimedOut: timed out reading the response $url',
      );
      expect(
        RequestCancelled(requested).toString(),
        'RequestCancelled: $url was cancelled',
      );
      expect(
        ConnectionFailed(requested).toString(),
        'ConnectionFailed: could not reach $url',
      );
      expect(
        ConnectionFailed(requested, cause: 'refused').toString(),
        'ConnectionFailed: could not reach $url (refused)',
      );
      expect(
        SessionExpired(requested).toString(),
        'SessionExpired: not signed in for $url',
      );
      expect(NotFound(requested).toString(), 'NotFound: $url');
      expect(
        CacheUnavailable(requested).toString(),
        'CacheUnavailable: the server cache is unavailable, possibly '
        'rebuilding ($url)',
      );
      expect(
        RateLimited(
          const Duration(seconds: 900),
          requested,
          rawRetryAfter: '900',
        ).toString(),
        'RateLimited: $url refused for 900s (Retry-After: 900)',
      );
      expect(
        RateLimited(Duration.zero, requested).toString(),
        'RateLimited: $url refused for 0s (Retry-After: absent)',
      );
      expect(
        ServerFailure(500, 'boom', requested).toString(),
        'ServerFailure: 500 from $url: boom',
      );
      expect(
        NotAFileFinServerResponse(requested, 'text/html').toString(),
        'NotAFileFinServerResponse: $url answered text/html, '
        'not application/json',
      );
      expect(
        NotAFileFinServerResponse(requested, null).toString(),
        'NotAFileFinServerResponse: $url answered no content type, '
        'not application/json',
      );
      expect(
        InvalidCredentials(requested).toString(),
        'InvalidCredentials: $url rejected that username and password',
      );
      expect(
        MalformedResponse(requested, 'files[0] is null').toString(),
        'MalformedResponse: $url sent JSON we could not read: '
        'files[0] is null',
      );
    });

    test('redactUserInfo leaves a URL without userInfo untouched', () {
      // The identity arm matters as much as the stripping one: rebuilding
      // every URL through `replace` would be a silent normalisation applied
      // to the thing the message exists to identify.
      final plain = Uri.parse('https://filefin.example:8099/api/me?x=1#f');
      expect(redactUserInfo(plain), same(plain));
      expect(
        redactUserInfo(Uri.parse('https://sam:hunter2@h/a')).toString(),
        'https://h/a',
      );
    });

    test('a URL carrying userInfo never prints the credential (§9)', () {
      // A saved base URL may be typed as `https://user:pass@host/`. Nothing
      // in this package puts credentials there, but `requested` is echoed
      // into every message, and a message is a log line waiting to happen.
      final mapped = mapDioException(
        badResponse(500, 'boom'),
        requested: Uri.parse('https://sam:hunter2@filefin.example/api/me'),
      );
      expect(mapped.toString(), isNot(contains('hunter2')));
      expect(mapped.toString(), isNot(contains('sam')));
      expect(mapped.toString(), contains('filefin.example'));
    });

    test('the hierarchy is exhaustively switchable with no default arm', () {
      // A `sealed` hierarchy the compiler can check is what lets the UI layer
      // handle every failure explicitly. If a variant is added without a UI
      // arm, this switch stops compiling — which is the point.
      String describe(FileFinApiException e) => switch (e) {
        RequestTimedOut() => 'timeout',
        RequestCancelled() => 'cancelled',
        ConnectionFailed() => 'unreachable',
        SessionExpired() => 'signed out',
        NotFound() => 'missing',
        CacheUnavailable() => 'busy',
        RateLimited() => 'slow down',
        ServerFailure() => 'server error',
        NotAFileFinServerResponse() => 'not a FileFin server',
        MalformedResponse() => 'unreadable',
        CertificateNotTrusted() => 'unknown certificate',
        CertificatePinMismatch() => 'certificate changed',
        InvalidCredentials() => 'wrong password',
        MalformedIdentifier() => 'bad id from the server',
        BadRequest() => 'the request was wrong',
        TranscodingDisabled() => 'transcoding is off',
      };
      expect(
        describe(
          mapDioException(
            transport(DioExceptionType.cancel),
            requested: requested,
          ),
        ),
        'cancelled',
      );
    });
  });
}

/// A stand-in for the `SocketException` dio would carry in a real refusal.
///
/// A real one is constructible, but it prints an OS-specific message that
/// differs between macOS and Linux, and a test asserting on it would fail on
/// the other machine for a reason that has nothing to do with the mapping.
class SocketishCause implements Exception {
  const SocketishCause(this.message);

  /// What the OS said.
  final String message;

  @override
  String toString() => 'SocketishCause($message)';
}
