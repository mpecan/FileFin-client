import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:test/test.dart';

/// A real TLS server on loopback, serving `test/support/certs/server_<name>`.
///
/// Real `bindSecure`, real handshake, real `X509Certificate` — the only part of
/// F15 that a stub would render meaningless, because what is under test is
/// precisely what the TLS stack does with our two callbacks.
///
/// It exists because the `filefin` binary has **no TLS listener at all** (no
/// `ListenAndServeTLS`, no certificate flag anywhere in `internal/` or `cmd/`,
/// verified at v0.20.3): TLS is a reverse-proxy concern upstream. So SPEC.md
/// §10's "a self-signed server connects only after explicit accept" is met
/// against a Dart TLS server rather than a real FileFin, and STATE.md and
/// docs/risks.md say so.
class TlsStub {
  TlsStub._(this._server, this.seen);

  final HttpServer _server;

  /// Every path the server was actually asked for.
  ///
  /// The assertion that matters most in this file is that this list is
  /// **empty** after a refusal: "blocking" measured rather than claimed.
  final List<String> seen;

  static Future<TlsStub> serving(String name) async {
    final context = SecurityContext()
      ..useCertificateChain('test/support/certs/server_$name.crt')
      ..usePrivateKey('test/support/certs/server_$name.key');
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final seen = <String>[];
    unawaited(
      server.forEach((request) async {
        seen.add(request.uri.path);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"needsSetup":false,"version":"0.20.3"}');
        await request.response.close();
      }),
    );
    return TlsStub._(server, seen);
  }

  Uri get baseUrl => Uri.parse('https://127.0.0.1:${_server.port}');

  Future<void> close() => _server.close(force: true);
}

/// The fingerprint of a committed test certificate, read from the PEM on disk.
///
/// Computed rather than hard-coded, so regenerating the pair is one command
/// instead of a hunt through assertions — and so the assertions compare our
/// digest against the certificate itself rather than against a number someone
/// once pasted. `README.md` records the `openssl x509 -fingerprint -sha256`
/// output that proves the two agree.
///
/// The DER is the PEM's base64 payload. It is extracted here rather than taken
/// from an `X509Certificate`, because dart:io only hands one over during a live
/// handshake — which is the thing under test.
CertificateFingerprint derFingerprint(String name) {
  final pem = File('test/support/certs/server_$name.crt').readAsStringSync();
  final body = pem
      .split('\n')
      .where((line) => !line.startsWith('-----'))
      .join();
  return CertificateFingerprint.fromDer(base64.decode(body));
}

void main() {
  late Dio dio;

  Dio dioFor(TlsStub stub, CertificatePinner pinner) {
    final client = Dio(
      fileFinBaseOptions(
        baseUrl: stub.baseUrl,
        timeout: const Duration(seconds: 5),
      ),
    )..httpClientAdapter = pinnedAdapter(pinner);
    addTearDown(client.close);
    return client;
  }

  Future<FileFinApiException> failureFrom(
    Dio client,
    CertificatePinner pinner,
    Uri url,
  ) async {
    try {
      await client.getUri<dynamic>(url);
      fail('the request should not have completed');
    } on DioException catch (e) {
      return mapDioException(e, requested: url, pinner: pinner);
    }
  }

  test('no pin: an untrusted certificate blocks and names itself', () async {
    final stub = await TlsStub.serving('a');
    addTearDown(stub.close);
    final pinner = CertificatePinner();
    dio = dioFor(stub, pinner);
    final url = stub.baseUrl.replace(path: '/api/state');

    final failure = await failureFrom(dio, pinner, url);

    expect(failure, isA<CertificateNotTrusted>());
    final e = failure as CertificateNotTrusted;
    expect(e.fingerprint, derFingerprint('a').value);
    expect(e.subject, contains('filefin-test-a'));
    expect(e.issuer, contains('filefin-test-a'));
    expect(e.validTo.isAfter(DateTime.now()), isTrue);
    // The measurement that turns "blocking" from a claim into a fact: the
    // refusal happened inside the handshake, so nothing was ever sent.
    expect(stub.seen, isEmpty);
  });

  test(
    'pinned to the certificate it serves: the request goes through',
    () async {
      final stub = await TlsStub.serving('a');
      addTearDown(stub.close);
      final pinner = CertificatePinner(pin: derFingerprint('a'));
      dio = dioFor(stub, pinner);

      final response = await dio.getUri<dynamic>(
        stub.baseUrl.replace(path: '/api/state'),
      );

      expect(response.statusCode, 200);
      expect(stub.seen, ['/api/state']);
    },
  );

  test('pinned to A, served B: blocked, nothing sent, pin unchanged', () async {
    final stub = await TlsStub.serving('b');
    addTearDown(stub.close);
    final pinner = CertificatePinner(pin: derFingerprint('a'));
    dio = dioFor(stub, pinner);
    final url = stub.baseUrl.replace(path: '/api/state');

    final failure = await failureFrom(dio, pinner, url);

    expect(failure, isA<CertificatePinMismatch>());
    final e = failure as CertificatePinMismatch;
    expect(e.expected, derFingerprint('a').value);
    expect(e.actual, derFingerprint('b').value);
    expect(stub.seen, isEmpty);
    // F15's blocking half must never re-accept. Nothing in this package can
    // write a pin, and this is the assertion that keeps it that way.
    expect(pinner.pin, derFingerprint('a'));
  });

  test('a pinned certificate is re-checked on a reused connection', () async {
    // `badCertificateCallback` is per CONNECTION, so on the second request
    // through a pooled socket it does not run at all. `validateCertificate` is
    // per RESPONSE and does. Two sequential requests on one Dio prove the
    // second is still checked rather than merely inheriting the first's
    // verdict.
    final stub = await TlsStub.serving('a');
    addTearDown(stub.close);
    final pinner = CertificatePinner(pin: derFingerprint('a'));
    dio = dioFor(stub, pinner);
    final url = stub.baseUrl.replace(path: '/api/state');

    expect((await dio.getUri<dynamic>(url)).statusCode, 200);
    expect((await dio.getUri<dynamic>(url)).statusCode, 200);
    expect(stub.seen, ['/api/state', '/api/state']);
    expect(pinner.decisionFor(url), isA<AcceptCertificate>());
  });

  test('a pin does not break the plain http F15 permits on a LAN', () async {
    // dio calls `validateCertificate` on every response including a
    // plain-http one, where the certificate is null. A pinner that rejected
    // null would make a saved LAN server stop working the moment a *different*
    // server's certificate was pinned.
    final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => plain.close(force: true));
    unawaited(
      plain.forEach((r) async {
        r.response.headers.contentType = ContentType.json;
        r.response.write('{"needsSetup":false,"version":"0.20.3"}');
        await r.response.close();
      }),
    );
    final pinner = CertificatePinner(pin: derFingerprint('a'));
    final url = Uri.parse('http://127.0.0.1:${plain.port}/api/state');
    final client = Dio(
      fileFinBaseOptions(baseUrl: url, timeout: const Duration(seconds: 5)),
    )..httpClientAdapter = pinnedAdapter(pinner);
    addTearDown(client.close);

    expect((await client.getUri<dynamic>(url)).statusCode, 200);
  });

  test('a pin, and only a pin, makes the client stop trusting OS roots', () {
    // Asserted as a property rather than through a request, because with a
    // self-signed certificate BOTH settings produce the same outcome — the
    // callback fires either way. They differ only for an OS-trusted
    // certificate, which needs a CA-signed cert for 127.0.0.1 and so cannot
    // be exercised here. This line IS the mechanism (see the doc comment on
    // `securityContext`), so it is pinned directly; the mutation gate found
    // it undefended, which is exactly the shape of gap it exists to find.
    expect(CertificatePinner().securityContext, isNull);
    expect(
      CertificatePinner(pin: derFingerprint('a')).securityContext,
      isNotNull,
    );
  });

  test('a recorded rejection does not explain an unrelated failure', () async {
    // The pinner remembers its last decision per host:port for as long as it
    // lives, so the mapper consults it only for the two exception types TLS
    // can produce. Without that narrowing a later timeout on the same server
    // would be reported as a certificate problem — a wrong story that sends
    // the user to check the wrong thing.
    final stub = await TlsStub.serving('b');
    addTearDown(stub.close);
    final pinner = CertificatePinner(pin: derFingerprint('a'));
    dio = dioFor(stub, pinner);
    final url = stub.baseUrl.replace(path: '/api/state');
    expect(await failureFrom(dio, pinner, url), isA<CertificatePinMismatch>());
    expect(pinner.decisionFor(url), isA<RejectChanged>());

    final options = RequestOptions(path: '/api/state');
    expect(
      mapDioException(
        DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
        requested: url,
        pinner: pinner,
      ),
      isA<RequestTimedOut>(),
    );
    expect(
      mapDioException(
        DioException(
          requestOptions: options,
          error: const SocketException('reset'),
        ),
        requested: url,
        pinner: pinner,
      ),
      isA<ConnectionFailed>(),
    );
  });

  test('the pinner never prints a pin it was not given', () {
    expect(CertificatePinner().toString(), 'CertificatePinner(unpinned)');
    expect(
      CertificatePinner(pin: derFingerprint('a')).toString(),
      'CertificatePinner(pinned ${derFingerprint('a')})',
    );
  });

  test('a TLS-shaped failure with no recorded decision stays a transport '
      'failure', () {
    // The mapper consults the pinner only for the two TLS exception types, and
    // only when a decision was actually recorded. A pinner that has judged
    // nothing must not turn an unrelated handshake error into a pin story.
    final pinner = CertificatePinner();
    final url = Uri.parse('https://filefin.example/api/state');
    // A HandshakeException under `DioExceptionType.unknown` — dio's default,
    // and measured at 5.11.0 to be exactly the shape a `badCertificateCallback`
    // refusal arrives in.
    final mapped = mapDioException(
      DioException(
        requestOptions: RequestOptions(path: '/api/state'),
        error: const HandshakeException('protocol version'),
      ),
      requested: url,
      pinner: pinner,
    );
    expect(mapped, isA<ConnectionFailed>());
  });

  test('every certificate message is asserted verbatim', () {
    final url = Uri.parse('https://filefin.example/api/state');
    expect(
      CertificateNotTrusted(
        url,
        fingerprint: 'aa:bb',
        subject: '/CN=filefin.lan',
        issuer: '/CN=filefin.lan',
        validTo: DateTime.utc(2030),
      ).toString(),
      'CertificateNotTrusted: https://filefin.example/api/state presented an '
      'untrusted certificate (/CN=filefin.lan, issued by /CN=filefin.lan, '
      'valid to 2030-01-01T00:00:00.000Z). SHA-256 aa:bb',
    );
    expect(
      CertificatePinMismatch(
        url,
        expected: 'aa:bb',
        actual: 'cc:dd',
      ).toString(),
      'CertificatePinMismatch: https://filefin.example/api/state presented '
      'cc:dd, but aa:bb was pinned. Nothing was sent.',
    );
  });
}
