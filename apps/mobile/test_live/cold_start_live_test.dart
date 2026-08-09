@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/live.dart';

/// **F2's cold start, against the real binary.**
///
/// M7.3 built it and proved every branch over a fake `SecretStore`. What a fake
/// cannot establish is that the value `filefin_api` stored is a cookie *this
/// server* will accept later — the store round-trips whatever it is handed, so
/// a client that saved the wrong header, or seeded the jar at the wrong path,
/// passes every unit test in the tree and fails on a phone.
///
/// **Building a second client over the same store IS the app restart**, from
/// `filefin_api`'s side: the jar, the interceptor and the in-memory generation
/// are all per client, and nothing but the store survives. The half that is
/// genuinely device-only — whether the Keychain hands the value back after a
/// reboot — is `docs/verification-backlog.md` row J and stays there.
///
/// Live calls happen in plain `test()` bodies, never inside `testWidgets`: a
/// request begun under `FakeAsync` registers its timers in that zone and never
/// completes (measured at M3.0, re-learned at M3.7).
void main() {
  const server = ServerId('cold-start');
  late FileFinTestServer binary;
  late InMemorySecretStore secrets;

  setUp(() async {
    // `flutter_test`'s binding installs an HttpOverrides that answers 400 for
    // every request. Restoring real sockets is what makes this a live suite.
    HttpOverrides.global = null;
    binary = await liveServer();
    secrets = InMemorySecretStore();
    await liveApiFor(binary, secrets, id: server).login(seededCredentials);
  });

  test('a fresh client restores the session, no password typed', () async {
    // The whole of F2. Nothing here types anything, and the only thing that
    // has happened since the sign-in is that a new client was built.
    final relaunched = liveApiFor(binary, secrets, id: server);

    await relaunched.restore();

    expect(await relaunched.categories(), isNotEmpty);
    expect((await relaunched.me()).user, seededCredentials.username);
  });

  test(
    'a server restart before the launch is renewed silently (F3, L1)',
    () async {
      // The case F2 exists for, and the one nothing has ever tested from a cold
      // start: the stored cookie is dead before the app is even open, so
      // `restore()` 401s, F3 re-authenticates from the stored password, and the
      // user sees a library rather than a password field.
      final before = await secrets.read(server, SecretKind.session);
      await binary.restart();
      // `username` is `settings.json`'s `lastUser`, which is exactly what
      // `main.dart` passes. It is not decoration: `_renew` reads the username
      // from memory, so a relaunched client without one has a perfectly good
      // stored password and nothing to use it with — see the test below.
      final relaunched = liveApiFor(
        binary,
        secrets,
        id: server,
        username: seededCredentials.username,
      );

      await relaunched.restore();

      expect(await relaunched.categories(), isNotEmpty);
      // A NEW cookie, which is what makes the launch after this one silent too
      // rather than repeating the renewal every time.
      expect(await secrets.read(server, SecretKind.session), isNot(before));
    },
  );

  test(
    'without the saved username there is nothing silent to renew from',
    () async {
      // The other half of the pair above, and the reason `lastUser` is in
      // `settings.json` at all. It is not a secret, and F2 cannot work without
      // it: the password lives in the platform store, the username does not,
      // and `_renew` needs both. Losing the settings file therefore costs a
      // password prompt even though the Keychain is intact — which is worth
      // knowing before someone "simplifies" `lastUser` away.
      await binary.restart();
      final relaunched = liveApiFor(binary, secrets, id: server);

      await expectLater(relaunched.restore(), throwsA(isA<SessionExpired>()));
    },
  );

  test(
    'with the password gone, the same restart is a loud SessionExpired',
    () async {
      // The negative control. Without it the test above passes just as happily
      // against a client that treats every failure as success, and F2's promise
      // would be "it looks signed in" rather than "it is".
      await secrets.delete(server, SecretKind.password);
      await binary.restart();
      final relaunched = liveApiFor(
        binary,
        secrets,
        id: server,
        username: seededCredentials.username,
      );

      await expectLater(relaunched.restore(), throwsA(isA<SessionExpired>()));

      // And the dead cookie is gone with it, so the next launch is a clean
      // sign-in rather than a retry of a value that can only ever be wrong.
      expect(await secrets.read(server, SecretKind.session), isNull);
    },
  );

  test(
    'a different ServerId in the same store has nothing to restore',
    () async {
      // The namespace, against a session a real server issued rather than a
      // string a test wrote. This is the assertion F11 rests on, one layer
      // below the picker.
      final other = liveApiFor(
        binary,
        secrets,
        id: const ServerId('elsewhere'),
      );

      await expectLater(other.restore(), throwsA(isA<SessionExpired>()));
    },
  );
}
