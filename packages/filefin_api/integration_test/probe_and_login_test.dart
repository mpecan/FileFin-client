@Timeout(Duration(seconds: 30))
library;

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// F1 and F2 against the real binary.
///
/// The unit suite proves the probe's *rule*; this proves the rule matches what
/// FileFin actually sends — including the SPA catch-all, which is the thing
/// that makes a status check worthless and which no stub can be evidence for.
void main() {
  late FileFinTestServer server;
  late FileFinClient client;
  late InMemorySecretStore secrets;

  setUp(() async {
    server = await startServer();
    secrets = InMemorySecretStore();
    client = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: secrets,
    );
    addTearDown(client.close);
  });

  test('the real server probes as a FileFin server (F1)', () async {
    final result = await client.probeServer();
    expect(result, isA<FileFinServer>());
    expect((result as FileFinServer).version, isNotEmpty);
  });

  test('a path the server does not route answers 200 text/html', () async {
    // The reason F1 is a content-type-and-payload check. Verified here against
    // the binary rather than quoted from the doc, because it is the single
    // assumption the whole probe rests on.
    final wrong = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl.replace(path: '/definitely-not-filefin'),
      secrets: InMemorySecretStore(),
    );
    addTearDown(wrong.close);
    final result = await wrong.probeServer();
    expect(result, isA<NotAFileFinServer>());
    expect((result as NotAFileFinServer).reason, contains('text/html'));
  });

  test(
    'an address with nothing on it is unreachable, not "not FileFin"',
    () async {
      final dead = FileFinClient.forServer(
        server: seededServer,
        baseUrl: Uri.parse('http://127.0.0.1:${await FixtureRun.freePort()}'),
        secrets: InMemorySecretStore(),
        timeout: const Duration(seconds: 3),
      );
      addTearDown(dead.close);
      expect(await dead.probeServer(), isA<ServerUnreachable>());
    },
  );

  test('login stores the session and the password (F2)', () async {
    final result = await client.login(seededCredentials);

    expect(result.user, seededCredentials.username);
    expect(result.admin, isTrue, reason: 'the seeded account is the admin');
    expect(
      await secrets.read(seededServer, SecretKind.session),
      isNotEmpty,
      reason: 'the real Set-Cookie must have reached the secure store',
    );
    expect(
      await secrets.read(seededServer, SecretKind.password),
      seededCredentials.password,
    );
  });

  test('a wrong password is InvalidCredentials, not a session loss', () async {
    await expectLater(
      client.login(
        Credentials(
          username: seededCredentials.username,
          password: 'not the password',
        ),
      ),
      throwsA(isA<InvalidCredentials>()),
    );
    expect(await secrets.read(seededServer, SecretKind.password), isNull);
  });

  test('logging out really ends the session server-side', () async {
    await client.login(seededCredentials);
    expect(await client.me(), isA<AuthResult>());

    await client.logout();

    // The cookie is gone locally AND the password with it, so the 401 that
    // follows cannot be silently repaired — which is what "signed out" has to
    // mean for it to mean anything.
    await expectLater(client.me(), throwsA(isA<SessionExpired>()));
  });

  test('a call with no session at all is a session loss', () async {
    await expectLater(client.categories(), throwsA(isA<SessionExpired>()));
  });
}
