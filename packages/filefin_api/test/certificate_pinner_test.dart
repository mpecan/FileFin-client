import 'dart:async';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/tls_stub.dart';

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

  test('F1 s probe hands a certificate question to the USER (F15)', () async {
    // Until M7.5 `probe()` was never given a pinner, so `mapDioException`
    // could not build a certificate error and the refusal collapsed into
    // `ConnectionFailed` -> `ServerUnreachable`. F1 renders that as "Nothing
    // answered at that address" — about a self-signed server that answered
    // perfectly well, which is F15's stated common case, with no way to accept
    // it. Every shipped client had this defect.
    final stub = await TlsStub.serving('a');
    addTearDown(stub.close);
    final client = FileFinClient.forServer(
      server: const ServerId('tls'),
      baseUrl: stub.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(client.close);

    await expectLater(
      client.probeServer(),
      throwsA(isA<CertificateNotTrusted>()),
    );
    // Thrown rather than returned, and nothing was sent: the refusal happened
    // inside the handshake.
    expect(stub.bytesReceived, 0);
  });

  test('a pinned certificate lets the probe through (F15)', () async {
    final stub = await TlsStub.serving('a');
    addTearDown(stub.close);
    final client = FileFinClient.forServer(
      server: const ServerId('tls'),
      baseUrl: stub.baseUrl,
      secrets: InMemorySecretStore(),
      pin: derFingerprint('a'),
    );
    addTearDown(client.close);

    expect(await client.probeServer(), isA<FileFinServer>());
  });

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
    expect(stub.bytesReceived, 0);
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

  group("a private CA, which is F15's stated common case", () {
    // Every test above serves a SELF-SIGNED certificate, where the chain is one
    // certificate long and leaf == root. That is exactly what hid the M2
    // defect: `badCertificateCallback` is handed the certificate at which
    // verification FAILED, which on a real `[leaf, CA]` chain is the CA, so the
    // pin was compared against the CA and the leaf was never examined until
    // after the request — cookie included — had been sent. `server_c` is a leaf
    // issued by `ca`, and `server_d` is a second leaf from the same CA standing
    // in for an impostor.

    test('the prompt names the LEAF, not the CA that signed it', () async {
      final stub = await TlsStub.serving('c');
      addTearDown(stub.close);
      final pinner = CertificatePinner();
      dio = dioFor(stub, pinner);
      final url = stub.baseUrl.replace(path: '/api/state');

      final failure = await failureFrom(dio, pinner, url);

      expect(failure, isA<CertificateNotTrusted>());
      final e = failure as CertificateNotTrusted;
      // The whole finding in three lines: the value the user is asked to
      // compare against their server must be their server's.
      expect(e.fingerprint, derFingerprint('c').value);
      expect(e.fingerprint, isNot(caFingerprint().value));
      expect(e.subject, contains('filefin-test-c'));
      expect(e.issuer, contains('filefin-test-ca'));
      expect(stub.bytesReceived, 0);
    });

    test('pinning the CA does not admit the leaf it signed, and no '
        'credential leaves', () async {
      final stub = await TlsStub.serving('c');
      addTearDown(stub.close);
      final pinner = CertificatePinner(pin: caFingerprint());
      dio = dioFor(stub, pinner);
      final url = stub.baseUrl.replace(path: '/api/state');
      // A cookie jar with a live session in it, because "the pin blocked" and
      // "the session cookie stayed on the device" are different claims and only
      // the second one is what F15 is for.
      final jar = DefaultCookieJar();
      await jar.saveFromResponse(stub.baseUrl, [
        Cookie(sessionCookieName, 'a-live-session')..path = '/',
      ]);
      dio.interceptors.add(CookieManager(jar));

      final failure = await failureFrom(dio, pinner, url);

      expect(failure, isA<CertificatePinMismatch>());
      expect(
        (failure as CertificatePinMismatch).actual,
        derFingerprint('c').value,
        reason: 'the certificate compared must be the leaf',
      );
      expect(stub.bytesReceived, 0);
      expect(stub.received, isEmpty);
      expect(stub.received.join(), isNot(contains('a-live-session')));
    });

    test(
      'pinned to the leaf the server really serves: it goes through',
      () async {
        // The other half of the same defect, and the one that made a private-CA
        // deployment unusable: before the fix a CORRECT pin — the value
        // `openssl x509 -fingerprint -sha256` prints for the server's own
        // certificate — was refused, because the comparison never saw it.
        final stub = await TlsStub.serving('c');
        addTearDown(stub.close);
        final pinner = CertificatePinner(pin: derFingerprint('c'));
        dio = dioFor(stub, pinner);

        final response = await dio.getUri<dynamic>(
          stub.baseUrl.replace(path: '/api/state'),
        );

        expect(response.statusCode, 200);
        expect(stub.seen, ['/api/state']);
      },
    );

    test('an impostor holding another certificate from the same CA is '
        'blocked', () async {
      final stub = await TlsStub.serving('d');
      addTearDown(stub.close);
      final pinner = CertificatePinner(pin: derFingerprint('c'));
      dio = dioFor(stub, pinner);
      final url = stub.baseUrl.replace(path: '/api/state');

      final failure = await failureFrom(dio, pinner, url);

      expect(failure, isA<CertificatePinMismatch>());
      final e = failure as CertificatePinMismatch;
      expect(e.expected, derFingerprint('c').value);
      expect(e.actual, derFingerprint('d').value);
      expect(stub.bytesReceived, 0);
    });
  });

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
    expect(stub.bytesReceived, 0);
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
      'cc:dd, but aa:bb was pinned. The connection was refused.',
    );
  });
}
