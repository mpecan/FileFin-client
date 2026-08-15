@Timeout(Duration(seconds: 30))
library;

import 'package:dio/dio.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// **M2's exit criterion.** A mid-test server restart is invisible to the
/// caller (F3, L1).
///
/// This is the one thing a stub cannot establish. Sessions live in the real
/// server's memory and die with the process (`auth.go`, `sessionStore`), so
/// restarting the binary reproduces the exact failure F3 exists for — real
/// sockets, a real jar, a real `Set-Cookie` — rather than a 401 a test chose
/// to send.
///
/// It comes with its **negative control**: without a stored password the same
/// restart must fail loudly. A recovery test with no such control passes just
/// as happily against a client that swallows every error.
void main() {
  late FileFinTestServer server;
  late FileFinClient client;
  late InMemorySecretStore secrets;
  late int logins;

  setUp(() async {
    server = await startServer();
    secrets = InMemorySecretStore();
    final counter = _LoginCounter();
    logins = 0;
    client = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: secrets,
    );
    client.authDio.interceptors.add(counter);
    counter.onCount = () => logins++;
    addTearDown(client.close);
  });

  test('a mid-test restart is invisible to the caller (F3, L1)', () async {
    await client.login(seededCredentials);
    final before = await client.categories();
    expect(before, isNotEmpty, reason: 'the seeded library has two categories');

    await server.restart();

    final after = await client.categories();
    expect(after, before);
    expect(logins, 2, reason: 'the initial login plus exactly one silent one');
  });

  test('eight concurrent requests after a restart cause one re-auth', () async {
    await client.login(seededCredentials);
    await client.categories();
    await server.restart();

    final results = await Future.wait([
      for (var i = 0; i < 8; i++) client.categories(),
    ]);

    expect(results, hasLength(8));
    for (final r in results) {
      expect(r, isNotEmpty);
    }
    // The whole point of the generation counter and the in-flight future. The
    // server locks an account after five failed logins in fifteen minutes, so
    // a client that fired eight would be one bad password away from locking a
    // user out of their own server.
    expect(logins, 2);
  });

  test('without a stored password the same restart fails loudly', () async {
    await client.login(seededCredentials);
    await client.categories();
    await secrets.delete(seededServer, SecretKind.password);

    await server.restart();

    await expectLater(client.categories(), throwsA(isA<SessionExpired>()));
  });

  test('a restored session survives without sending a password', () async {
    // F2's other half: `restore` seeds the jar from the secure store and
    // validates with `GET /api/me`, so a warm start does not need a password
    // at all. The server is NOT restarted here — the session is still valid.
    await client.login(seededCredentials);
    final fresh = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: secrets,
    );
    addTearDown(fresh.close);

    final me = await (fresh.sessions as SessionManager).restore();

    expect(me.user, seededCredentials.username);
  });
}

class _LoginCounter extends Interceptor {
  void Function()? onCount;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.endsWith('/api/login')) onCount?.call();
    handler.next(options);
  }
}
