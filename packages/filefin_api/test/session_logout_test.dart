/// `SessionManager.logout`, split out of `session_test.dart` at M7.8 when the
/// SPA-catch-all case took that file past `just file-size`'s 400-line soft
/// warning — and a gate warning may fall or hold, never rise. Same split, same
/// reason, as `settings_selection_test.dart` at M7.4.
library;

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

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
      stub.on('POST', urls.login.path, responder);

  StubResponse goodLogin([String value = 'sess-1']) => StubResponse.json(
    <String, Object?>{'user': 'testuser', 'admin': true},
    headers: {'set-cookie': setSession(value)},
  );

  group('logout', () {
    test('drops the cookie the server expires, and both secrets', () async {
      serveLogin((_) => goodLogin());
      await sessions.login(creds);
      expect(await jar.loadForRequest(urls.base), isNotEmpty);
      // `auth.go:195` writes Go's MaxAge:-1, which goes on the wire as
      // Max-Age=0. Whether cookie_jar honours that is asserted, not assumed.
      stub.on(
        'POST',
        urls.logout.path,
        (_) => const StubResponse(
          status: 204,
          body: '',
          contentType: 'text/plain',
          headers: {'set-cookie': 'filefin_session=; Path=/; Max-Age=0'},
        ),
      );

      await sessions.logout();

      // The METHOD, asserted directly. `logout` reads nothing back, so every
      // other assertion here passes just as happily against a GET — which the
      // real binary answers `200 text/html` from the SPA catch-all, leaving the
      // session alive forever. `just it` holds the server half of this.
      final logout = stub.requests.last;
      expect(logout.path, urls.logout.path);
      expect(logout.method, 'POST');

      expect(await jar.loadForRequest(urls.base), isEmpty);
      expect(await secrets.read(server, SecretKind.session), isNull);
      expect(await secrets.read(server, SecretKind.password), isNull);
    });

    test('the SPA catch-all is not a sign-out (M7.8)', () async {
      // `logout` reads nothing back, so until M7.8 nothing on its path could
      // notice a route that did not match. The stub answers an unregistered
      // path exactly the way the real server does — `200 text/html` from the
      // catch-all outside the route table (`server.go:352`) — so registering
      // nothing IS the case under test, and the previous version of this file
      // says in a comment what it could not assert.
      //
      // The local half must still happen: someone who taps sign out ends up
      // signed out here whatever the server said, which is what the `finally`
      // is for and what the case below asserts for a dead server.
      serveLogin((_) => goodLogin());
      await sessions.login(creds);

      await expectLater(
        sessions.logout(),
        throwsA(isA<NotAFileFinServerResponse>()),
      );

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
        'POST',
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
}
