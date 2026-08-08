import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/stub_server.dart';

const server = ServerId('home');
const creds = Credentials(username: 'testuser', password: 'TestPassw0rd!23');

/// A `Set-Cookie` shaped like the one `auth.go:177` writes.
String setSession(String value) =>
    'filefin_session=$value; Path=/; HttpOnly; SameSite=Lax';

void main() {
  late StubServer stub;
  late FileFinUrls urls;
  late CookieJar jar;
  late InMemorySecretStore secrets;
  late Dio authDio;
  late DateTime clock;
  late SessionManager sessions;

  setUp(() async {
    stub = await StubServer.start();
    addTearDown(stub.close);
    urls = FileFinUrls(stub.baseUrl);
    jar = DefaultCookieJar();
    secrets = InMemorySecretStore();
    clock = DateTime.utc(2026, 8, 8, 12);
    authDio = Dio(
      fileFinBaseOptions(
        baseUrl: stub.baseUrl,
        timeout: const Duration(seconds: 5),
      ),
    )..interceptors.add(CookieManager(jar));
    addTearDown(authDio.close);
    sessions = SessionManager(
      authDio: authDio,
      urls: urls,
      jar: jar,
      secrets: secrets,
      server: server,
      now: () => clock,
    );
  });

  void serveLogin(StubResponder responder) =>
      stub.on(urls.login.path, responder);

  StubResponse goodLogin([String value = 'sess-1']) => StubResponse.json(
    <String, Object?>{'user': 'testuser', 'admin': true},
    headers: {'set-cookie': setSession(value)},
  );

  group('login (F2)', () {
    test(
      'stores the password AND the session, and bumps the generation',
      () async {
        serveLogin((_) => goodLogin());
        expect(sessions.generation, 0);

        final result = await sessions.login(creds);

        expect(result.user, 'testuser');
        expect(await secrets.read(server, SecretKind.password), creds.password);
        expect(await secrets.read(server, SecretKind.session), 'sess-1');
        expect(sessions.generation, 1);
      },
    );

    test(
      'a 401 is bad credentials, not a session loss, and stores nothing',
      () async {
        // The one route where a 401 does NOT mean L1. Treating it as one is an
        // infinite retry loop against a limiter that locks the account after
        // five tries.
        serveLogin((_) => const StubResponse.unauthorized());

        await expectLater(
          sessions.login(creds),
          throwsA(isA<InvalidCredentials>()),
        );
        expect(await secrets.read(server, SecretKind.password), isNull);
        expect(await secrets.read(server, SecretKind.session), isNull);
        expect(sessions.generation, 0);
        expect(stub.countFor(urls.login.path), 1);
      },
    );

    test('a 200 that sets no cookie is a malformed response', () async {
      // The password would otherwise be stored against a session that does
      // not exist, and every later call would 401 into a re-auth loop.
      serveLogin((_) => StubResponse.json(<String, Object?>{'user': 'x'}));

      await expectLater(
        sessions.login(creds),
        throwsA(isA<MalformedResponse>()),
      );
      expect(await secrets.read(server, SecretKind.password), isNull);
      expect(sessions.generation, 0);
    });

    test('the request body is exactly what auth.go:132 reads', () async {
      serveLogin((_) => goodLogin());
      await sessions.login(creds);
      expect(
        stub.requests.single.body,
        '{"username":"testuser","password":"TestPassw0rd!23"}',
      );
    });
  });

  group('rate limiting (429)', () {
    test('a 429 blocks the next attempt with NO second request', () async {
      serveLogin(
        (_) => const StubResponse(
          status: 429,
          body: 'too many requests',
          contentType: 'text/plain',
          headers: {'retry-after': '900'},
        ),
      );

      await expectLater(
        sessions.login(creds),
        throwsA(
          isA<RateLimited>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 900),
          ),
        ),
      );
      expect(stub.countFor(urls.login.path), 1);

      await expectLater(sessions.login(creds), throwsA(isA<RateLimited>()));
      // The point of the whole mechanism: still ONE request. Retrying into a
      // limiter is how a locked account stays locked.
      expect(stub.countFor(urls.login.path), 1);
    });

    test('the block expires on the injected clock, not on wall time', () async {
      var attempts = 0;
      serveLogin((_) {
        attempts++;
        return attempts == 1
            ? const StubResponse(
                status: 429,
                body: 'too many requests',
                contentType: 'text/plain',
                headers: {'retry-after': '900'},
              )
            : goodLogin();
      });

      await expectLater(sessions.login(creds), throwsA(isA<RateLimited>()));
      clock = clock.add(const Duration(seconds: 899));
      await expectLater(sessions.login(creds), throwsA(isA<RateLimited>()));
      expect(stub.countFor(urls.login.path), 1);

      clock = clock.add(const Duration(seconds: 2));
      await sessions.login(creds);
      expect(stub.countFor(urls.login.path), 2);
    });

    test('a successful login clears the block', () async {
      serveLogin((_) => goodLogin());
      await sessions.login(creds);
      clock = clock.add(const Duration(days: 1));
      await sessions.login(creds);
      expect(stub.countFor(urls.login.path), 2);
    });
  });

  group('reauthenticate — the concurrency guard', () {
    test('a stale generation returns without a request at all', () async {
      serveLogin((_) => goodLogin());
      await sessions.login(creds);
      expect(sessions.generation, 1);

      // A request issued before a refresh but 401ing after it. Someone else
      // already fixed the session; logging in again would burn one of five
      // attempts for nothing.
      await sessions.reauthenticate(seenGeneration: 0);
      expect(stub.countFor(urls.login.path), 1);
    });

    test('eight concurrent callers cause exactly ONE login', () async {
      serveLogin((_) => goodLogin());
      await sessions.login(creds);
      final generation = sessions.generation;

      await Future.wait([
        for (var i = 0; i < 8; i++)
          sessions.reauthenticate(seenGeneration: generation),
      ]);

      // Without the in-flight future this is 2..9; without the generation
      // counter it is 9. The test discriminates between all three designs.
      expect(stub.countFor(urls.login.path), 2);
      expect(sessions.generation, generation + 1);
    });

    test(
      'without a stored password it fails loudly and sends nothing',
      () async {
        serveLogin((_) => goodLogin());
        await sessions.login(creds);
        await secrets.delete(server, SecretKind.password);

        await expectLater(
          sessions.reauthenticate(seenGeneration: sessions.generation),
          throwsA(isA<SessionExpired>()),
        );
        expect(stub.countFor(urls.login.path), 1);
      },
    );

    test(
      'with no login ever performed there is no username to reuse',
      () async {
        await expectLater(
          sessions.reauthenticate(seenGeneration: 0),
          throwsA(isA<SessionExpired>()),
        );
        expect(stub.requests, isEmpty);
      },
    );

    test('a rate-limited re-auth fails fast with no network call', () async {
      serveLogin(
        (_) => const StubResponse(
          status: 429,
          body: 'too many requests',
          contentType: 'text/plain',
          headers: {'retry-after': '900'},
        ),
      );
      await expectLater(sessions.login(creds), throwsA(isA<RateLimited>()));
      await secrets.write(server, SecretKind.password, creds.password);

      await expectLater(
        sessions.reauthenticate(seenGeneration: sessions.generation),
        throwsA(isA<RateLimited>()),
      );
      expect(stub.countFor(urls.login.path), 1);
    });
  });

  group('restore', () {
    test(
      'seeds the jar from the store and validates with GET /api/me',
      () async {
        await secrets.write(server, SecretKind.session, 'stored-session');
        stub.on(
          urls.me.path,
          (_) => StubResponse(
            status: 200,
            body: fixtureText('me.json'),
            contentType: 'application/json',
          ),
        );

        final result = await sessions.restore();

        expect(result.user, 'testuser');
        expect(stub.requests.single.path, '/api/me');
        expect(stub.requests.single.cookie, 'filefin_session=stored-session');
      },
    );

    test(
      'with nothing stored it is a session loss, and sends nothing',
      () async {
        await expectLater(sessions.restore(), throwsA(isA<SessionExpired>()));
        expect(stub.requests, isEmpty);
      },
    );

    test('a 401 from /api/me is the ordinary F3 path, not an error', () async {
      await secrets.write(server, SecretKind.session, 'expired');
      stub.on(urls.me.path, (_) => const StubResponse.unauthorized());
      await expectLater(sessions.restore(), throwsA(isA<SessionExpired>()));
    });
  });

  group('logout', () {
    test('drops the cookie the server expires, and both secrets', () async {
      serveLogin((_) => goodLogin());
      await sessions.login(creds);
      expect(await jar.loadForRequest(urls.base), isNotEmpty);
      // `auth.go:195` writes Go's MaxAge:-1, which goes on the wire as
      // Max-Age=0. Whether cookie_jar honours that is asserted, not assumed.
      stub.on(
        urls.logout.path,
        (_) => const StubResponse(
          status: 204,
          body: '',
          contentType: 'text/plain',
          headers: {'set-cookie': 'filefin_session=; Path=/; Max-Age=0'},
        ),
      );

      await sessions.logout();

      expect(await jar.loadForRequest(urls.base), isEmpty);
      expect(await secrets.read(server, SecretKind.session), isNull);
      expect(await secrets.read(server, SecretKind.password), isNull);
    });

    test('signing out of a server that is down still signs you out', () async {
      serveLogin((_) => goodLogin());
      await sessions.login(creds);
      await stub.close();

      await expectLater(sessions.logout(), throwsA(isA<ConnectionFailed>()));

      expect(await secrets.read(server, SecretKind.session), isNull);
      expect(await secrets.read(server, SecretKind.password), isNull);
      expect(await jar.loadForRequest(urls.base), isEmpty);
    });

    test(
      'cookie_jar honours Max-Age=0 on its own — measured, not assumed',
      () async {
        // The explicit clear in `logout` exists for the failure path above, not
        // because the jar needs help. This is the measurement that says so, and
        // it is a test rather than a comment because a dependency upgrade could
        // change the answer.
        await jar.saveFromResponse(urls.base, [
          Cookie(sessionCookieName, 'v')..path = '/',
        ]);
        expect(await jar.loadForRequest(urls.base), hasLength(1));
        await jar.saveFromResponse(urls.base, [
          Cookie(sessionCookieName, '')
            ..path = '/'
            ..maxAge = 0,
        ]);
        expect(await jar.loadForRequest(urls.base), isEmpty);
      },
    );

    test('a certificate pin survives logging out', () async {
      // The pin is about the SERVER's identity, not the user's. Clearing it on
      // logout would re-prompt for trust-on-first-use every time someone signs
      // out, training them to click through the one dialog F15 exists for.
      await secrets.write(server, SecretKind.certificatePin, 'aa:bb');
      stub.on(
        urls.logout.path,
        (_) => const StubResponse(
          status: 204,
          body: '',
          contentType: 'text/plain',
        ),
      );
      await sessions.logout();
      expect(await secrets.read(server, SecretKind.certificatePin), 'aa:bb');
    });
  });

  group('nothing prints a secret (§9, NF4)', () {
    test('Credentials redacts its password', () {
      expect(creds.toString(), 'Credentials(testuser, <redacted>)');
      expect(creds.toString(), isNot(contains(creds.password)));
    });

    test('SessionManager prints no password, session or username', () async {
      serveLogin((_) => goodLogin('super-secret-session'));
      await sessions.login(creds);
      final printed = sessions.toString();
      expect(printed, isNot(contains(creds.password)));
      expect(printed, isNot(contains('super-secret-session')));
      expect(printed, 'SessionManager(home, generation 1, <redacted>)');
    });
  });
}
