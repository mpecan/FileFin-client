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
    client = ClientHarness.build(stub, urls, secrets).client;
    addTearDown(client.close);
  });

  StubResponse categoriesJson() => StubResponse(
    status: 200,
    body: fixtureText('categories.json'),
    contentType: 'application/json',
  );

  group('endpoints round-trip the captured payloads (§8)', () {
    test('categories', () async {
      stub.on('GET', urls.categories.path, (_) => categoriesJson());
      final result = await client.categories();
      expect(result.map((c) => c.id), [
        const CategoryId(1),
        const CategoryId(2),
      ]);
      expect(result.first.parentId, const CategoryId(0));
    });

    test('categoryMedia', () async {
      final url = urls.categoryMedia(const CategoryId(1));
      stub.on(
        'GET',
        url.path,
        (_) => StubResponse(
          status: 200,
          body: fixtureText('category_media.json'),
          contentType: 'application/json',
        ),
      );
      final result = await client.categoryMedia(const CategoryId(1));
      expect(result.single.id, const MediaId('e4285edb34d5'));
      expect(result.single.title, 'Direct Play Movie');
    });

    test('mediaDetail', () async {
      const id = MediaId('e4285edb34d5');
      stub.on(
        'GET',
        urls.mediaDetail(id).path,
        (_) => StubResponse(
          status: 200,
          body: fixtureText('media_detail_directplay.json'),
          contentType: 'application/json',
        ),
      );
      final detail = await client.mediaDetail(id);
      expect(detail.title, 'Direct Play Movie');
      expect(detail.files.single.transcode, isFalse);
      expect(detail.tags, contains('direct-play'));
    });

    test('me', () async {
      stub.on(
        'GET',
        urls.me.path,
        (_) => StubResponse(
          status: 200,
          body: fixtureText('me.json'),
          contentType: 'application/json',
        ),
      );
      expect((await client.me()).user, 'testuser');
    });

    test('probe, on the client, does not go through F3', () async {
      stub.on(
        'GET',
        urls.state.path,
        (_) => StubResponse(
          status: 200,
          body: fixtureText('state.json'),
          contentType: 'application/json',
        ),
      );
      expect(await client.probeServer(), isA<FileFinServer>());
    });

    test('a JSON object where an array belongs fails the response', () {
      stub.on(
        'GET',
        urls.categories.path,
        (_) => StubResponse.json(<String, Object?>{'not': 'a list'}),
      );
      return expectLater(
        client.categories(),
        throwsA(isA<MalformedResponse>()),
      );
    });

    test('a list whose element is not an object fails the whole response', () {
      // NOT filtered out. Dropping the bad row silently is the failure G5
      // forbids; the caller sees a loud error naming the shape instead.
      stub.on('GET', urls.categories.path, (_) => StubResponse.json([1, 2]));
      return expectLater(
        client.categories(),
        throwsA(isA<MalformedResponse>()),
      );
    });
  });

  group('forServer wires the whole thing', () {
    test('probes, logs in, browses and logs out over one client', () async {
      // The factory an app actually calls, exercised end to end against the
      // stub. Without this the unit suite would only ever test the injected
      // constructor, and the wiring an app depends on — jar, pinned adapter,
      // session manager, interceptor order — would be covered by nothing.
      var issued = 0;
      stub
        ..on(
          'GET',
          urls.state.path,
          (_) => StubResponse(
            status: 200,
            body: fixtureText('state.json'),
            contentType: 'application/json',
          ),
        )
        ..on('POST', urls.login.path, (_) {
          issued++;
          return StubResponse(
            status: 200,
            body: fixtureText('login.json'),
            contentType: 'application/json',
            headers: {'set-cookie': 'filefin_session=live-$issued; Path=/'},
          );
        })
        ..on(
          'POST',
          urls.logout.path,
          (_) => const StubResponse(
            status: 204,
            body: '',
            contentType: 'text/plain',
            headers: {'set-cookie': 'filefin_session=; Path=/; Max-Age=0'},
          ),
        )
        ..on(
          'GET',
          urls.categories.path,
          (r) => r.cookie == 'filefin_session=live-1'
              ? categoriesJson()
              : const StubResponse.unauthorized(),
        );

      final wired = FileFinClient.forServer(
        server: serverId,
        baseUrl: stub.baseUrl,
        secrets: secrets,
        timeout: const Duration(seconds: 5),
      );
      addTearDown(wired.close);

      expect(await wired.probeServer(), isA<FileFinServer>());
      // The whole captured `login.json`, not just `user` (§8). The hand-written
      // literal this replaced omitted the three fields below, which the real
      // server does send — so the login happy path proved only that we can
      // spell our own field names, and the fixture `check-fixtures.sh` keeps a
      // checksum of was read by no test at all.
      final signedIn = await wired.login(creds);
      expect(signedIn.user, 'testuser');
      expect(signedIn.admin, isTrue);
      expect(signedIn.alias, '');
      expect(signedIn.mdlUsername, '');
      expect(signedIn.malUsername, '');
      expect(await wired.categories(), hasLength(2));
      expect(await secrets.read(serverId, SecretKind.password), creds.password);

      await wired.logout();

      expect(await secrets.read(serverId, SecretKind.session), isNull);
      expect(await wired.jar.loadForRequest(stub.baseUrl), isEmpty);
    });

    test('an unpinned client still trusts the OS for ordinary HTTPS', () {
      // `forServer` with no pin must leave the default SecurityContext in
      // place; building every client on `withTrustedRoots: false` would make
      // a perfectly ordinary public HTTPS server unreachable.
      final wired = FileFinClient.forServer(
        server: serverId,
        baseUrl: stub.baseUrl,
        secrets: secrets,
      );
      addTearDown(wired.close);
      expect(wired.pinner?.pin, isNull);
      expect(wired.pinner?.securityContext, isNull);
    });
  });
}
