import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/client_harness.dart';
import 'support/fixtures.dart';
import 'support/stub_server.dart';

void main() {
  late StubServer stub;
  late FileFinUrls urls;
  late FileFinClient client;
  late InMemorySecretStore secrets;

  setUp(() async {
    stub = await StubServer.start();
    addTearDown(stub.close);
    urls = FileFinUrls(stub.baseUrl);
    secrets = InMemorySecretStore();
    client = buildTokenClient(stub, urls, secrets);
    addTearDown(client.close);
  });

  StubResponse categoriesJson() => StubResponse(
    status: 200,
    body: fixtureText('categories.json'),
    contentType: 'application/json',
  );

  StubResponse meOk() => StubResponse(
    status: 200,
    body: fixtureText('me.json'),
    contentType: 'application/json',
  );

  test(
    'the bearer header rides on every request, not just the sign-in one',
    () async {
      stub
        ..on(
          'GET',
          urls.me.path,
          (request) => request.authorization == 'Bearer ffpat_good'
              ? meOk()
              : const StubResponse.unauthorized(),
        )
        ..on(
          'GET',
          urls.categories.path,
          (request) => request.authorization == 'Bearer ffpat_good'
              ? categoriesJson()
              : const StubResponse.unauthorized(),
        );

      await client.signInWithToken(const ApiToken('ffpat_good'));
      // Bounded rather than a bare await: an interceptor that never calls
      // handler.next/reject on some path leaves dio's request Future pending
      // forever, and that must fail this test loudly rather than hang it.
      final result = await client.categories().timeout(
        const Duration(seconds: 5),
      );

      expect(result, hasLength(3));
    },
  );

  test(
    'a token revoked after sign-in is InvalidToken, with no retry or replay',
    () async {
      stub.on('GET', urls.me.path, (_) => meOk());
      await client.signInWithToken(const ApiToken('ffpat_good'));

      // The server now answers as if the token had been revoked from Settings.
      stub.on(
        'GET',
        urls.categories.path,
        (_) => const StubResponse.unauthorized(),
      );

      await expectLater(
        client.categories().timeout(const Duration(seconds: 5)),
        throwsA(isA<InvalidToken>()),
      );

      // Exactly one request: unlike a password session, nothing here retries.
      expect(stub.countFor(urls.categories.path), 1);
    },
  );

  test(
    'a non-401 failure passes through untouched, not turned into InvalidToken',
    () async {
      stub.on('GET', urls.me.path, (_) => meOk());
      await client.signInWithToken(const ApiToken('ffpat_good'));
      stub.on(
        'GET',
        urls.categories.path,
        (_) => const StubResponse(
          status: 500,
          body: 'internal error',
          contentType: 'text/plain',
        ),
      );

      await expectLater(
        client.categories().timeout(const Duration(seconds: 5)),
        throwsA(isA<ServerFailure>()),
      );
    },
  );

  test('forTokenServer wires a real client against a real socket', () async {
    // Every other test in this file goes through `buildTokenClient`, which
    // injects a `Dio` for testability the way `client_endpoints_test.dart`'s
    // password-mode equivalent does. This is the sibling of ITS
    // `FileFinClient.forServer` case: the public factory itself, unmodified,
    // against the stub's real loopback socket.
    stub.on('GET', urls.me.path, (_) => meOk());
    final wired = FileFinClient.forTokenServer(
      server: const ServerId('wired-token'),
      baseUrl: stub.baseUrl,
      secrets: InMemorySecretStore(),
      timeout: const Duration(seconds: 5),
    );
    addTearDown(wired.close);

    final result = await wired
        .signInWithToken(const ApiToken('ffpat_good'))
        .timeout(const Duration(seconds: 5));

    expect(result.user, 'testuser');
  });

  test('forTokenServer defaults to a 15s timeout, like forServer', () {
    final wired = FileFinClient.forTokenServer(
      server: const ServerId('wired-default-timeout'),
      baseUrl: stub.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(wired.close);

    expect(wired.authDio.options.connectTimeout, const Duration(seconds: 15));
  });

  test('TokenAuthInterceptor prints no token', () {
    final session = TokenAuthSession(
      authDio: client.authDio,
      urls: urls,
      secrets: secrets,
      server: const ServerId('home'),
    );

    expect(
      TokenAuthInterceptor(session: session).toString(),
      'TokenAuthInterceptor(<redacted>)',
    );
  });

  test('login() on a token-mode client fails loudly rather than misfiring', () {
    expect(
      () => client.login(const Credentials(username: 'x', password: 'y')),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('password-mode client'),
        ),
      ),
    );
  });

  test(
    'signInWithToken() on a password-mode client fails loudly too',
    () async {
      final passwordClient = ClientHarness.build(stub, urls, secrets).client;
      addTearDown(passwordClient.close);

      expect(
        () => passwordClient.signInWithToken(const ApiToken('x')),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('token-mode client'),
          ),
        ),
      );
    },
  );

  test('logout() on a token-mode client forgets the stored token', () async {
    stub.on('GET', urls.me.path, (_) => meOk());
    await client.signInWithToken(const ApiToken('ffpat_good'));
    expect(await secrets.read(serverId, SecretKind.token), 'ffpat_good');

    await client.logout();

    expect(await secrets.read(serverId, SecretKind.token), isNull);
  });
}
