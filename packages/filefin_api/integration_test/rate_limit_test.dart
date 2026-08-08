@Timeout(Duration(seconds: 60))
library;

import 'package:dio/dio.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// The login limiter, on a server **this suite alone owns and then discards**.
///
/// Five failures against one account in fifteen minutes lock that account for
/// fifteen minutes (`loginlimit.go:15-27`). The limiter is in memory and dies
/// with the process, so a fresh server per run is what keeps this suite from
/// poisoning every other one — sharing an instance would 429 the browse suite
/// for a quarter of an hour and the failure would look like a client bug.
///
/// That is also why the suite is small. It establishes that the 429 and its
/// `Retry-After` are real and correctly parsed; everything about *how the
/// client behaves* while blocked is unit-tested against an injected clock,
/// because the alternative is a test that waits fifteen minutes.
void main() {
  test(
    'five bad logins earn a 429 with Retry-After in whole seconds',
    () async {
      final server = await startServer();
      final client = FileFinClient.forServer(
        server: seededServer,
        baseUrl: server.baseUrl,
        secrets: InMemorySecretStore(),
      );
      addTearDown(client.close);
      final wrong = Credentials(
        username: seededCredentials.username,
        password: 'wrong',
      );

      final seen = <Object>[];
      for (var attempt = 0; attempt < 8; attempt++) {
        try {
          await client.login(wrong);
          fail('a wrong password must never succeed');
        } on FileFinApiException catch (e) {
          seen.add(e);
          if (e is RateLimited) break;
        }
      }

      expect(
        seen.whereType<InvalidCredentials>(),
        isNotEmpty,
        reason: 'the first failures are ordinary bad credentials',
      );
      final limited = seen.whereType<RateLimited>();
      expect(limited, hasLength(1), reason: 'the run stops at the first 429');
      // `auth.go:149` writes `int(retry.Seconds()) + 1`, so the header is whole
      // seconds and our integer-only parse is the right one. Asserting it is
      // positive rather than exactly 900 keeps the test about the contract
      // rather than about how long the limiter happens to be configured for.
      expect(limited.single.retryAfter.inSeconds, greaterThan(0));
      expect(int.tryParse(limited.single.rawRetryAfter!), isNotNull);
    },
  );

  test('a blocked client refuses the next attempt without a request', () async {
    // The client-side half, measured end to end: once blocked, `login` throws
    // before it reaches the network. Retrying into a limiter is how a locked
    // account stays locked.
    //
    // **Counted, not timed.** This used to assert that the refusal took under
    // 100 ms, which cannot discriminate: a loopback 429 was measured at
    // 0.31 ms, three hundred times under the threshold, so making
    // `_refuseWhileBlocked` a no-op kept the test green — the client went to
    // the network, the server 429'd again, and the same typed error arrived.
    // A counting interceptor on `authDio` observes the thing the test claims
    // to be about, the way the unit suite already does.
    final server = await startServer();
    final client = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(client.close);
    final logins = _LoginCounter();
    client.authDio.interceptors.add(logins);
    final wrong = Credentials(
      username: seededCredentials.username,
      password: 'wrong',
    );

    var blocked = false;
    for (var attempt = 0; attempt < 8 && !blocked; attempt++) {
      try {
        await client.login(wrong);
      } on RateLimited {
        blocked = true;
      } on InvalidCredentials {
        continue;
      }
    }
    expect(
      blocked,
      isTrue,
      reason: 'eight wrong passwords must trip the limit',
    );

    final sent = logins.count;
    expect(sent, greaterThan(0), reason: 'the interceptor is really counting');

    await expectLater(client.login(wrong), throwsA(isA<RateLimited>()));

    expect(
      logins.count,
      sent,
      reason: 'refusing locally must not involve a round trip',
    );
  });
}

/// Counts `POST /api/login` at the transport level.
class _LoginCounter extends Interceptor {
  int count = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.endsWith('/api/login')) count++;
    handler.next(options);
  }
}
