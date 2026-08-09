@Timeout(Duration(seconds: 90))
library;

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// F11 on the wire: **two real `filefin` servers, two accounts, one process.**
///
/// Every piece of the mechanism landed at M2 — `FileFinClient.forServer` gives
/// each `ServerId` its own cookie jar, its own secret namespace and its own
/// pinner — and nothing ever ran two of them against two servers. What a
/// single-server suite cannot see is the only failure that matters here: a
/// cookie jar shared between clients, or `secretKeyFor` handed the wrong
/// `ServerId`, both of which look exactly like success when the two servers
/// hold the same library and the same account.
///
/// So the two servers are made **distinguishable in both directions**: the
/// accounts differ (`fixture_run.dart`'s `secondUser`), and the third test
/// writes to one library and reads the other. The reaper in
/// `tool/run-integration.sh` runs once at script start rather than between
/// suites, and `FixtureRun` gives each copy its own `HOME`, cache and free
/// port — which is why two can coexist at all (M7.0/E-2).
void main() {
  late FileFinTestServer alpha;
  late FileFinTestServer beta;
  late InMemorySecretStore secrets;
  late FileFinClient alphaClient;
  late FileFinClient betaClient;

  const alphaId = ServerId('alpha');
  const betaId = ServerId('beta');
  const betaCredentials = Credentials(
    username: secondUser,
    password: secondPassword,
  );

  setUp(() async {
    alpha = await startServer();
    beta = await startServer();
    // ONE store for both, which is what the app has: `PlatformSecretStore` is a
    // process-wide singleton and the namespace is the only thing keeping two
    // servers' credentials apart.
    secrets = InMemorySecretStore();
    alphaClient = FileFinClient.forServer(
      server: alphaId,
      baseUrl: alpha.baseUrl,
      secrets: secrets,
    );
    betaClient = FileFinClient.forServer(
      server: betaId,
      baseUrl: beta.baseUrl,
      secrets: secrets,
    );
    addTearDown(alphaClient.close);
    addTearDown(betaClient.close);
  });

  test('two servers really are two servers', () async {
    // The premise the rest of this file rests on. `FixtureRun` binds port 0 per
    // copy; if that ever stopped being true, every assertion below would pass
    // against one server talking to itself.
    expect(alpha.baseUrl, isNot(beta.baseUrl));
    expect(alpha.baseUrl.port, isNot(beta.baseUrl.port));
  });

  test('each client signs in as its own account and stays as it', () async {
    final alphaAuth = await alphaClient.login(seededCredentials);
    final betaAuth = await betaClient.login(betaCredentials);

    expect(alphaAuth.user, seededUser);
    expect(betaAuth.user, secondUser);
    // Re-asked AFTER the other has signed in, because a shared jar would only
    // show itself on the second call.
    expect((await alphaClient.me()).user, seededUser);
    expect((await betaClient.me()).user, secondUser);
  });

  test("one server's session cookie is refused by the other", () async {
    await alphaClient.login(seededCredentials);
    await betaClient.login(betaCredentials);
    final alphaSession = await secrets.read(alphaId, SecretKind.session);
    final betaSession = await secrets.read(betaId, SecretKind.session);

    expect(alphaSession, isNotNull);
    expect(betaSession, isNot(alphaSession));
    // Asked through a bare `HttpClient` that shares no jar and no interceptor
    // with either client, so nothing it reports can be repaired on the way out.
    expect(await meStatusWithCookie(alpha.baseUrl, alphaSession!), 200);
    expect(await meStatusWithCookie(beta.baseUrl, alphaSession), 401);
    expect(await meStatusWithCookie(alpha.baseUrl, betaSession!), 401);
  });

  test("each server's password is stored under its own key", () async {
    await alphaClient.login(seededCredentials);
    await betaClient.login(betaCredentials);

    expect(
      await secrets.read(alphaId, SecretKind.password),
      seededCredentials.password,
    );
    expect(
      await secrets.read(betaId, SecretKind.password),
      betaCredentials.password,
    );
  });

  test("F3 renews from THIS server's password, not the other's", () async {
    // **The one test that can catch `secretKeyFor` being handed the wrong
    // `ServerId`**, and the reason the second account had to exist. Both
    // servers are copies of one seed, so both accept `testuser` — a client that
    // read alpha's stored password would renew against beta *successfully* and
    // every status-code assertion would stay green. What it could not do is
    // come back as the right USER.
    await alphaClient.login(seededCredentials);
    await betaClient.login(betaCredentials);
    // BOTH, so the assertion holds whichever login wrote last. With one
    // namespace for the store, restarting only beta would renew from the value
    // beta itself had just written and pass.
    await alpha.restart();
    await beta.restart();

    // The 401 each of these provokes is F3's ordinary path: re-auth, replay,
    // no throw.
    expect((await alphaClient.me()).user, seededUser);
    expect((await betaClient.me()).user, secondUser);
  });

  test('a write on one library is invisible to the other', () async {
    await alphaClient.login(seededCredentials);
    await betaClient.login(betaCredentials);
    final categories = await alphaClient.categories();
    final films = await alphaClient.categoryMedia(
      categories.firstWhere((c) => c.leaf == 'Films').id,
    );
    final item = films.single.id;

    await alphaClient.setFavorite(item, favorite: true);

    expect(
      (await alphaClient.home()).favorites.map((m) => m.id),
      contains(item),
    );
    expect((await betaClient.home()).favorites, isEmpty);
  });

  test('signing out of one server leaves the other signed in (§9)', () async {
    // The half F11 exists for. `SessionManager.logout` clears the jar and both
    // secrets in a `finally`; if it cleared them by key prefix rather than by
    // `ServerId`, or if the two clients shared a jar, this is where it shows.
    await alphaClient.login(seededCredentials);
    await betaClient.login(betaCredentials);

    await alphaClient.logout();

    expect(await secrets.read(alphaId, SecretKind.session), isNull);
    expect(await secrets.read(alphaId, SecretKind.password), isNull);
    expect(await secrets.read(betaId, SecretKind.password), isNotNull);
    expect((await betaClient.me()).user, secondUser);
  });
}
