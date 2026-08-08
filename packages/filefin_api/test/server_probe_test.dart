import 'package:dio/dio.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/stub_server.dart';

void main() {
  late StubServer stub;
  late Dio dio;
  late FileFinUrls urls;

  setUp(() async {
    stub = await StubServer.start();
    addTearDown(stub.close);
    urls = FileFinUrls(stub.baseUrl);
    dio = Dio(
      fileFinBaseOptions(
        baseUrl: stub.baseUrl,
        timeout: const Duration(seconds: 5),
      ),
    );
    addTearDown(dio.close);
  });

  /// Registers [response] on the real `/api/state` path, taken from
  /// `FileFinUrls` rather than typed out, so renaming the route in `ApiPaths`
  /// cannot leave this stub answering the old one.
  void serveState(StubResponse response) =>
      stub.on(urls.state.path, (_) => response);

  test('a captured real /api/state is a FileFin server (F1)', () async {
    serveState(
      StubResponse(
        status: 200,
        body: fixtureText('state.json'),
        contentType: 'application/json',
      ),
    );
    final result = await probe(dio: dio, urls: urls);
    expect(result, isA<FileFinServer>());
    expect((result as FileFinServer).version, '0.20.3');
  });

  test('needsSetup:true is a different outcome, not a failure', () async {
    serveState(StubResponse.json({'needsSetup': true, 'version': '0.20.3'}));
    final result = await probe(dio: dio, urls: urls);
    expect(result, isA<FileFinServerNeedsSetup>());
    expect((result as FileFinServerNeedsSetup).version, '0.20.3');
  });

  test('the SPA catch-all answers 200 and is still not FileFin (F1)', () async {
    // No route registered at all, so the stub answers the way the real server
    // does for an unmatched path: `200 text/html` with index.html
    // (`server.go:352`, verified live at v0.20.3). A status check would call
    // this a success. F1 is a content-type-and-payload check for this reason.
    final result = await probe(dio: dio, urls: urls);
    expect(result, isA<NotAFileFinServer>());
    // Verbatim, not `contains`. The reason is what a user reads in the dialog
    // that refuses their address, and it is mutable source nothing else in
    // the suite looks at — the first mutation run over this file left a
    // survivor inside exactly this literal (M1.10 found the same shape in
    // `filefin_core`'s ArgumentError messages).
    expect(
      (result as NotAFileFinServer).reason,
      '${urls.state} answered text/html; charset=utf-8 rather than '
      'application/json, which is what any web page answers',
    );
  });

  test('JSON with a version but no needsSetup is NOT FileFin', () async {
    // THE CASE THAT SEPARATES A REAL CHECK FROM A CONTENT-TYPE-ONLY ONE.
    // Any JSON API answers `application/json`; plenty answer a `version`. The
    // probe accepts only a body carrying BOTH documented keys, and deleting
    // either half of that conjunction is what this test exists to catch.
    serveState(StubResponse.json({'version': '1'}));
    final result = await probe(dio: dio, urls: urls);
    expect(result, isA<NotAFileFinServer>());
    expect(
      (result as NotAFileFinServer).reason,
      'the JSON at ${urls.state} is missing needsSetup, so it is not a '
      'FileFin state response',
    );
  });

  test('JSON with needsSetup but no version is NOT FileFin', () async {
    serveState(StubResponse.json({'needsSetup': false}));
    final result = await probe(dio: dio, urls: urls);
    expect(result, isA<NotAFileFinServer>());
    expect(
      (result as NotAFileFinServer).reason,
      'the JSON at ${urls.state} is missing version, so it is not a '
      'FileFin state response',
    );
  });

  test('a charset parameter on the media type is tolerated', () async {
    serveState(
      StubResponse(
        status: 200,
        body: fixtureText('state.json'),
        contentType: 'application/json; charset=utf-8',
      ),
    );
    expect(await probe(dio: dio, urls: urls), isA<FileFinServer>());
  });

  test('APPLICATION/JSON is the same media type', () async {
    serveState(
      StubResponse(
        status: 200,
        body: fixtureText('state.json'),
        contentType: 'APPLICATION/JSON',
      ),
    );
    expect(await probe(dio: dio, urls: urls), isA<FileFinServer>());
  });

  test('an empty JSON object is missing BOTH keys, and says so', () async {
    // The `join(' and ')` arm: a body that fails half the conjunction and a
    // body that fails all of it are different messages, and only this case
    // exercises the second.
    serveState(StubResponse.json(<String, Object?>{}));
    final result = await probe(dio: dio, urls: urls);
    expect(
      (result as NotAFileFinServer).reason,
      'the JSON at ${urls.state} is missing needsSetup and version, so it is '
      'not a FileFin state response',
    );
  });

  test('a JSON array where an object belongs is NOT FileFin', () async {
    serveState(StubResponse.json([1, 2, 3]));
    final result = await probe(dio: dio, urls: urls);
    expect(result, isA<NotAFileFinServer>());
  });

  test('a server that never answers is unreachable, not "not FileFin"', () {
    // The `RequestTimedOut` arm of the same conjunction. The stub responder
    // returns null, so the request is received and never answered — a hung
    // server, without a `sleep` a loaded machine could turn into a flake.
    final slow = Dio(
      fileFinBaseOptions(
        baseUrl: stub.baseUrl,
        timeout: const Duration(milliseconds: 300),
      ),
    );
    addTearDown(slow.close);
    stub.on(urls.state.path, (_) => null);
    return expectLater(
      probe(dio: slow, urls: urls),
      completion(
        isA<ServerUnreachable>().having(
          (r) => r.cause,
          'cause',
          isA<RequestTimedOut>().having(
            (e) => e.phase,
            'phase',
            RequestPhase.receive,
          ),
        ),
      ),
    );
  });

  test('a truncated JSON body is NOT FileFin, not a crash', () async {
    serveState(
      const StubResponse(
        status: 200,
        body: '{"needsSetup":fal',
        contentType: 'application/json',
      ),
    );
    expect(await probe(dio: dio, urls: urls), isA<NotAFileFinServer>());
  });

  test('a field of the wrong wire type is NOT FileFin, not a crash', () async {
    // Both keys are present, so the conjunction passes and the failure
    // happens inside `ServerState.fromJson` — a generated decoder raising
    // `_TypeError`. `decodeModel` is what stops a raw Dart `TypeError`
    // reaching a user whose server merely changed a field's type.
    serveState(StubResponse.json({'needsSetup': 'yes', 'version': '0.20.3'}));
    final result = await probe(dio: dio, urls: urls);
    expect(result, isA<NotAFileFinServer>());
    expect((result as NotAFileFinServer).reason, contains('could not read'));
  });

  test('a non-2xx status is NOT FileFin, and the reason says which', () async {
    // `GET /api/state` is unauthenticated and always answers 200
    // (`install.go:24`), so anything else proves the thing at this URL is not
    // FileFin's state route — a proxy, a different app, or FileFin behind a
    // gateway that is not passing the request through.
    serveState(
      const StubResponse(
        status: 502,
        body: 'bad gateway',
        contentType: 'text/plain',
      ),
    );
    final result = await probe(dio: dio, urls: urls);
    expect(result, isA<NotAFileFinServer>());
    expect((result as NotAFileFinServer).reason, contains('502'));
  });

  test('nothing listening at all is unreachable, not "not FileFin"', () async {
    // The distinction matters to the user: "I cannot reach this address" and
    // "this address is something else" lead to different next actions.
    await stub.close();
    final result = await probe(dio: dio, urls: urls);
    expect(result, isA<ServerUnreachable>());
    expect((result as ServerUnreachable).cause, isA<ConnectionFailed>());
  });

  test(
    'cancellation propagates rather than becoming a verdict (NF5)',
    () async {
      final token = CancelToken();
      serveState(StubResponse.json({'needsSetup': false, 'version': '1'}));
      stub.on(urls.state.path, (_) {
        token.cancel();
        return null;
      });
      await expectLater(
        probe(dio: dio, urls: urls, cancelToken: token),
        throwsA(isA<RequestCancelled>()),
      );
    },
  );

  test('the probe issues exactly one GET, to /api/state', () async {
    serveState(
      StubResponse(
        status: 200,
        body: fixtureText('state.json'),
        contentType: 'application/json',
      ),
    );
    await probe(dio: dio, urls: urls);
    expect(stub.requests, hasLength(1));
    expect(stub.requests.single.method, 'GET');
    expect(stub.requests.single.path, '/api/state');
  });

  test('a probe result is exhaustively switchable with no default arm', () {
    String describe(ProbeResult r) => switch (r) {
      FileFinServer(:final version) => 'ready $version',
      FileFinServerNeedsSetup() => 'needs setup',
      NotAFileFinServer() => 'not filefin',
      ServerUnreachable() => 'unreachable',
    };
    expect(describe(const FileFinServer('0.20.3')), 'ready 0.20.3');
  });

  test('every probe result prints itself, verbatim', () {
    // These reach a bug report and a log line, and each is mutable source
    // nothing else in the suite reads. Same reasoning as the reasons above.
    expect(const FileFinServer('0.20.3').toString(), 'FileFinServer(0.20.3)');
    expect(
      const FileFinServerNeedsSetup('0.20.3').toString(),
      'FileFinServerNeedsSetup(0.20.3)',
    );
    expect(
      const NotAFileFinServer('it is a wiki').toString(),
      'NotAFileFinServer(it is a wiki)',
    );
    expect(
      const ServerUnreachable('refused').toString(),
      'ServerUnreachable(refused)',
    );
  });
}
