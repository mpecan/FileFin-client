import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/client_harness.dart';
import 'support/stub_server.dart';

/// The two things `fileFinBaseOptions` decides that dio would decide otherwise.
///
/// Both are one line in `transport.dart` and neither is visible in any endpoint
/// test, which is why they have a file: a default that has been overridden on
/// purpose looks exactly like a default nobody thought about, until something
/// puts it back.
void main() {
  late StubServer stub;
  late FileFinUrls urls;
  late FileFinClient client;

  setUp(() async {
    stub = await StubServer.start();
    addTearDown(stub.close);
    urls = FileFinUrls(stub.baseUrl);
    client = ClientHarness.build(stub, urls, InMemorySecretStore()).client;
    addTearDown(client.close);
  });

  test('a body that never ends times out too', () async {
    // **A fact about dio, pinned because we rely on it.** Its IO adapter sets
    // `receiveTimeout` on `request.close()`, which reads as time-to-HEADERS —
    // and M2's review predicted that a server which answers and then drips
    // two bytes every 100 ms would hang forever past the timeout. Measured
    // against dio 5.11.0 with `fileFinBaseOptions`, it does not: the deadline
    // covers the whole receive rather than resetting on each chunk, and the
    // drip aborts at the timeout like a stall does. So `transport.dart`'s
    // "applied to all three phases" is true — for this version. A dio upgrade
    // that made it an inactivity timer instead would make it false in
    // silence, which is what this test is for.
    final drip = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => drip.close(force: true));
    final timers = <Timer>[];
    addTearDown(() {
      for (final timer in timers) {
        timer.cancel();
      }
    });
    unawaited(
      drip.forEach((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.headers.contentLength = 100000;
        request.response.add(utf8.encode('{"a":'));
        await request.response.flush();
        timers.add(
          Timer.periodic(const Duration(milliseconds: 100), (_) {
            request.response.add(utf8.encode('  '));
            unawaited(request.response.flush());
          }),
        );
      }),
    );
    final dripUrls = FileFinUrls(Uri.parse('http://127.0.0.1:${drip.port}'));
    final slow = FileFinClient.forServer(
      server: serverId,
      baseUrl: dripUrls.base,
      secrets: InMemorySecretStore(),
      timeout: const Duration(milliseconds: 300),
    );
    addTearDown(slow.close);

    final started = DateTime.now();
    await expectLater(
      slow.categories(),
      throwsA(
        isA<RequestTimedOut>().having(
          (e) => e.phase,
          'phase',
          RequestPhase.receive,
        ),
      ),
    );
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 5)),
      reason: 'the drip must be cut off, not merely eventually abandoned',
    );
  });

  test('a redirect is refused, so a pinned origin cannot be downgraded '
      '(S5)', () async {
    // dio follows up to five redirects by default, and `validateCertificate`
    // only ever sees the connection that served the FINAL response. Measured
    // at M2: a pinned https origin answering `302 -> http://impostor/api/me`
    // had the redirect followed and the client decoded
    // `{"user":"attacker","admin":true}` as the pinned server's answer.
    //
    // The assertion that matters is the last one — the impostor was never
    // contacted at all. `throwsA` alone would pass against a client that
    // followed the redirect and then disliked the body.
    var impostorHits = 0;
    final impostor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => impostor.close(force: true));
    unawaited(
      impostor.forEach((request) async {
        impostorHits++;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"user":"attacker","admin":true}');
        await request.response.close();
      }),
    );
    stub.on(
      'GET',
      urls.me.path,
      (_) => StubResponse(
        status: 302,
        body: '',
        contentType: 'text/plain',
        headers: {'location': 'http://127.0.0.1:${impostor.port}/api/me'},
      ),
    );

    await expectLater(
      client.me(),
      throwsA(
        isA<ServerFailure>().having((e) => e.statusCode, 'statusCode', 302),
      ),
    );
    expect(impostorHits, 0, reason: 'the impostor was never contacted');
  });
}
