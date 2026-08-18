import 'package:dio/dio.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/stub_server.dart';

const server = ServerId('home');

void main() {
  late StubServer stub;
  late FileFinUrls urls;
  late InMemorySecretStore secrets;
  late TokenAuthSession session;

  setUp(() async {
    stub = await StubServer.start();
    addTearDown(stub.close);
    urls = FileFinUrls(stub.baseUrl);
    secrets = InMemorySecretStore();
    session = TokenAuthSession(
      authDio: Dio(
        fileFinBaseOptions(
          baseUrl: stub.baseUrl,
          timeout: const Duration(seconds: 5),
        ),
      ),
      urls: urls,
      secrets: secrets,
      server: server,
    );
  });

  StubResponse meOk() => StubResponse(
    status: 200,
    body: fixtureText('me.json'),
    contentType: 'application/json',
  );

  group('verify', () {
    test(
      'proves the token against GET /api/me, carrying it as Bearer',
      () async {
        stub.on(
          'GET',
          urls.me.path,
          (request) => request.authorization == 'Bearer ffpat_good'
              ? meOk()
              : const StubResponse.unauthorized(),
        );

        final result = await session.verify(const ApiToken('ffpat_good'));

        expect(result.user, 'testuser');
      },
    );

    test('stores the token only once proven', () async {
      stub.on('GET', urls.me.path, (_) => meOk());

      await session.verify(const ApiToken('ffpat_good'));

      expect(await secrets.read(server, SecretKind.token), 'ffpat_good');
    });

    test('a rejected token is InvalidToken, and nothing is stored', () async {
      stub.on('GET', urls.me.path, (_) => const StubResponse.unauthorized());

      await expectLater(
        session.verify(const ApiToken('ffpat_bad')),
        throwsA(isA<InvalidToken>()),
      );
      expect(await secrets.read(server, SecretKind.token), isNull);
    });
  });

  group('restore', () {
    test('with nothing stored, fails without a request', () async {
      await expectLater(session.restore(), throwsA(isA<SessionExpired>()));
      expect(stub.requests, isEmpty);
    });

    test('a stored token that still works restores silently', () async {
      await secrets.write(server, SecretKind.token, 'ffpat_good');
      stub.on(
        'GET',
        urls.me.path,
        (request) => request.authorization == 'Bearer ffpat_good'
            ? meOk()
            : const StubResponse.unauthorized(),
      );

      final result = await session.restore();

      expect(result.user, 'testuser');
    });

    test(
      'a stored token the server now rejects is deleted, not kept',
      () async {
        // Unlike a password session, there is no separate credential
        // underneath a token that might still be good — the token IS the
        // credential, so keeping a known-dead one serves nothing.
        await secrets.write(server, SecretKind.token, 'ffpat_revoked');
        stub.on('GET', urls.me.path, (_) => const StubResponse.unauthorized());

        await expectLater(session.restore(), throwsA(isA<InvalidToken>()));

        expect(await secrets.read(server, SecretKind.token), isNull);
      },
    );
  });

  test('resume is restore, for the AuthSession interface', () async {
    await secrets.write(server, SecretKind.token, 'ffpat_good');
    stub.on('GET', urls.me.path, (_) => meOk());

    await session.resume();

    expect(await session.headers(), {'Authorization': 'Bearer ffpat_good'});
  });

  test('forget deletes the stored token', () async {
    await secrets.write(server, SecretKind.token, 'ffpat_good');

    await session.forget();

    expect(await secrets.read(server, SecretKind.token), isNull);
  });

  group('headers', () {
    test('null before anything is proven or stored', () async {
      expect(await session.headers(), isNull);
    });

    test('the bearer header for a token proven this session', () async {
      stub.on('GET', urls.me.path, (_) => meOk());
      await session.verify(const ApiToken('ffpat_good'));

      expect(await session.headers(), {'Authorization': 'Bearer ffpat_good'});
    });

    test('the bearer header for a token restored from storage', () async {
      await secrets.write(server, SecretKind.token, 'ffpat_good');

      expect(await session.headers(), {'Authorization': 'Bearer ffpat_good'});
    });
  });

  group('headersSync', () {
    test('null before anything is proven this session', () {
      expect(session.headersSync, isNull);
    });

    test(
      'stays null for a token only in storage, unlike headers()',
      () async {
        // headersSync is the interceptor's fast path and deliberately never
        // consults SecretStore - that async read is exactly what it exists
        // to avoid inside onRequest.
        await secrets.write(server, SecretKind.token, 'ffpat_good');

        expect(session.headersSync, isNull);
      },
    );

    test('the bearer header once verify() has cached the token', () async {
      stub.on('GET', urls.me.path, (_) => meOk());
      await session.verify(const ApiToken('ffpat_good'));

      expect(session.headersSync, {'Authorization': 'Bearer ffpat_good'});
    });
  });

  test('prints no token', () {
    expect(session.toString(), 'TokenAuthSession(home, <redacted>)');
  });

  test('ApiToken prints no token', () {
    expect(const ApiToken('ffpat_secret').toString(), 'ApiToken(<redacted>)');
  });

  test(
    'an AuthSession that forgets to override toString still cannot leak',
    () {
      // The property `abstract base class` buys, mirrored from
      // `secret_store_test.dart`'s identical case for `SecretStore`: `base`
      // forces every subtype to extend rather than implement, so the
      // redacting `toString` is inherited rather than merely recommended.
      expect(
        _ForgetfulAuthSession().toString(),
        '_ForgetfulAuthSession(<redacted>)',
      );
    },
  );
}

/// An `AuthSession` that overrides nothing it is not forced to.
final class _ForgetfulAuthSession extends AuthSession {
  @override
  Future<void> forget() async {}

  @override
  Future<Map<String, String>?> headers() async => null;

  @override
  Future<void> resume() async {}
}
