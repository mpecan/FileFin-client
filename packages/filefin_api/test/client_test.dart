import 'package:dio/dio.dart';
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
  late LoginCounter logins;

  FileFinClient build({Duration timeout = const Duration(seconds: 5)}) {
    final harness = ClientHarness.build(stub, urls, secrets, timeout: timeout);
    logins = harness.logins;
    return harness.client;
  }

  setUp(() async {
    stub = await StubServer.start();
    addTearDown(stub.close);
    urls = FileFinUrls(stub.baseUrl);
    secrets = InMemorySecretStore();
    client = build();
    addTearDown(client.close);
  });

  StubResponse categoriesJson() => StubResponse(
    status: 200,
    body: fixtureText('categories.json'),
    contentType: 'application/json',
  );

  group('F3 — a 401 is routine (L1)', () {
    test('renews, replays, and the caller never sees the 401', () async {
      serveLogin(stub, urls);
      await client.login(creds);
      var protectedHits = 0;
      stub.on(urls.categories.path, (request) {
        protectedHits++;
        return request.cookie == 'filefin_session=sess-2'
            ? categoriesJson()
            : const StubResponse.unauthorized();
      });

      final result = await client.categories();

      expect(result, hasLength(2));
      expect(result.first.name, 'Films');
      expect(protectedHits, 2);
      expect(logins.count, 2);
      // Three requests in all: the 401, the renewal, the replay.
      expect(stub.requests, hasLength(4));
    });

    test('the replayed request carries the NEW cookie', () async {
      // THE ASSERTION THE WHOLE DESIGN RESTS ON. `dio.fetch` re-running the
      // interceptor chain is what lets `CookieManager` attach the cookie the
      // renewal just stored. If `fetch` ever bypassed the chain the replay
      // would reuse the dead cookie and 401 forever, and a test asserting only
      // the final status could not tell the difference.
      serveLogin(stub, urls);
      await client.login(creds);
      stub.on(
        urls.categories.path,
        (request) => request.cookie == 'filefin_session=sess-2'
            ? categoriesJson()
            : const StubResponse.unauthorized(),
      );

      await client.categories();

      final protectedRequests = stub.requests
          .where((r) => r.path == urls.categories.path)
          .toList();
      expect(protectedRequests.first.cookie, 'filefin_session=sess-1');
      expect(protectedRequests.last.cookie, 'filefin_session=sess-2');
    });

    test('exactly one retry: a second 401 is a session loss', () async {
      serveLogin(stub, urls);
      await client.login(creds);
      stub.on(urls.categories.path, (_) => const StubResponse.unauthorized());

      await expectLater(client.categories(), throwsA(isA<SessionExpired>()));

      expect(logins.count, 2, reason: 'one initial login and one renewal');
      expect(stub.countFor(urls.categories.path), 2);
    });

    test('eight concurrent 401s cause exactly one renewal', () async {
      serveLogin(stub, urls);
      await client.login(creds);
      stub.on(
        urls.categories.path,
        (request) => request.cookie == 'filefin_session=sess-2'
            ? categoriesJson()
            : const StubResponse.unauthorized(),
      );

      final results = await Future.wait([
        for (var i = 0; i < 8; i++) client.categories(),
      ]);

      expect(results, hasLength(8));
      for (final r in results) {
        expect(r, hasLength(2));
      }
      expect(logins.count, 2, reason: 'the initial login plus ONE renewal');
    });

    test('a renewal that is rate limited says so, not "signed out"', () async {
      // Reporting a 429 as `SessionExpired` would send the user to type a
      // password into an account that is locked for fifteen minutes.
      serveLogin(stub, urls);
      await client.login(creds);
      stub
        ..on(urls.categories.path, (_) => const StubResponse.unauthorized())
        ..on(
          urls.login.path,
          (_) => const StubResponse(
            status: 429,
            body: 'too many requests',
            contentType: 'text/plain',
            headers: {'retry-after': '900'},
          ),
        );

      await expectLater(
        client.categories(),
        throwsA(
          isA<RateLimited>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(seconds: 900),
          ),
        ),
      );
    });

    test('a login that itself 401s does not loop', () async {
      // The structural guard: `/api/login` runs on a Dio with no
      // AuthInterceptor, so its 401 cannot reach the retry logic at all.
      stub.on(urls.login.path, (_) => const StubResponse.unauthorized());

      await expectLater(
        client.login(creds),
        throwsA(isA<InvalidCredentials>()),
      );

      expect(logins.count, 1);
    });

    test('a 401 with no stored password fails loudly, once', () async {
      stub.on(urls.categories.path, (_) => const StubResponse.unauthorized());

      await expectLater(client.categories(), throwsA(isA<SessionExpired>()));

      expect(logins.count, 0, reason: 'nothing to log in with');
      expect(stub.countFor(urls.categories.path), 1);
    });
  });

  group('the caller stays in control (NF5)', () {
    test('a cancelled request is RequestCancelled, not a failure', () async {
      final token = CancelToken();
      stub.on(urls.categories.path, (_) {
        token.cancel();
        return null;
      });
      await expectLater(
        client.categories(cancelToken: token),
        throwsA(isA<RequestCancelled>()),
      );
    });

    test('a server that never answers times out', () async {
      client.close();
      client = build(timeout: const Duration(milliseconds: 300));
      addTearDown(client.close);
      stub.on(urls.categories.path, (_) => null);
      await expectLater(
        client.categories(),
        throwsA(
          isA<RequestTimedOut>().having(
            (e) => e.phase,
            'phase',
            RequestPhase.receive,
          ),
        ),
      );
    });
  });

  group('an identifier the server sent that cannot be a URL', () {
    test('an empty media id fails before any request is made', () async {
      // `MediaId('')` is `MediaDetail.id`'s own declared default, so any
      // payload with a missing id produces one. It must fail loudly rather
      // than addressing `/api/media`, which the SPA catch-all answers 200.
      await expectLater(
        client.mediaDetail(const MediaId('')),
        throwsA(
          isA<MalformedIdentifier>()
              .having((e) => e.value, 'value', '')
              .having((e) => e.field, 'field', 'media id'),
        ),
      );
      expect(stub.requests, isEmpty);
    });

    test('a dot-segment id fails the same way', () async {
      await expectLater(
        client.mediaDetail(const MediaId('..')),
        throwsA(isA<MalformedIdentifier>()),
      );
      expect(stub.requests, isEmpty);
    });

    test('the message names the value and says nothing was sent', () {
      expect(
        const MalformedIdentifier('..', 'media id').toString(),
        'MalformedIdentifier: ".." is not a usable media id, so no request '
        'was made',
      );
    });
  });

  test('a client prints which server it is, and no secret', () {
    expect(client.toString(), 'FileFinClient(home, ${stub.baseUrl})');
  });
}
