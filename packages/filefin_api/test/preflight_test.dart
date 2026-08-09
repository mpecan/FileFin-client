import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/client_harness.dart';
import 'support/stub_server.dart';

const _id = MediaId('919ac9caad25');
const _file = FileIndex(0);

/// `requirePlayable` — F12's pre-flight (M5.2).
///
/// Every status here was measured against a real `filefin` at v0.20.3 in
/// M5.0/E-A and E-K, including the two that are easy to get wrong: the `307`
/// carries `Content-Type: text/html` because Go's `http.Redirect` writes an
/// HTML body, and a `HEAD` `415` carries no body at all.
void main() {
  late StubServer stub;
  late FileFinUrls urls;
  late FileFinClient client;
  late String path;
  late String hlsPath;

  setUp(() async {
    stub = await StubServer.start();
    addTearDown(stub.close);
    urls = FileFinUrls(stub.baseUrl);
    client = ClientHarness.build(stub, urls, InMemorySecretStore()).client;
    addTearDown(client.close);
    // From `ApiPaths`, never a literal, so renaming a route cannot leave this
    // stub silently answering the old one.
    path = urls.file(_id, _file).path;
    hlsPath = urls.hlsIndex(_id, _file).path;
  });

  void serve(StubResponse response) => stub.on('HEAD', path, (_) => response);

  test('a 307 to HLS is success, and dio does not follow it', () async {
    serve(
      const StubResponse(
        status: 307,
        body: '<a href="…">Temporary Redirect</a>',
        contentType: 'text/html; charset=utf-8',
        headers: {'location': '/api/media/919ac9caad25/file/0/hls/index.m3u8'},
      ),
    );

    await client.requirePlayable(_id, _file);

    expect(stub.countFor(path), 1);
    // THE ASSERTION THAT PINS `followRedirects: false`. dio follows up to five
    // redirects by default, and turning that on would re-open M2's measured
    // downgrade attack for no benefit — libmpv follows the 307 itself.
    expect(stub.countFor(hlsPath), 0);
    expect(stub.requests.single.method, 'HEAD');
  });

  test('a 415 is TranscodingDisabled, naming the file route', () async {
    serve(
      const StubResponse(
        status: 415,
        body: '',
        contentType: 'text/plain; charset=utf-8',
      ),
    );

    await expectLater(
      client.requirePlayable(_id, _file),
      throwsA(
        isA<TranscodingDisabled>().having(
          (e) => e.requested,
          'requested',
          urls.file(_id, _file),
        ),
      ),
    );
  });

  test('a 200 and a 206 are both success', () async {
    serve(
      const StubResponse(status: 200, body: '', contentType: 'video/mp4'),
    );
    await client.requirePlayable(_id, _file);

    serve(
      const StubResponse(status: 206, body: '', contentType: 'video/mp4'),
    );
    await client.requirePlayable(_id, _file);
  });

  test('a 200 text/html is the SPA catch-all, not a playable file', () async {
    serve(
      const StubResponse(
        status: 200,
        body: '',
        contentType: 'text/html; charset=utf-8',
      ),
    );

    await expectLater(
      client.requirePlayable(_id, _file),
      throwsA(isA<NotAFileFinServerResponse>()),
    );
  });

  test('the HTML guard is 2xx-only, on BOTH sides of 300', () async {
    // The boundary the guard is written at, and it is not academic: Go's
    // `http.Redirect` writes an HTML body, so the 307 arrives as `text/html`
    // (M5.0/E-K). A guard applied to every status would refuse the SUCCESS
    // case and — because the SPA catch-all answers `200 text/html` — let the
    // real failure through. Below 300, HTML is the catch-all; at or above it,
    // HTML is Go's own redirect page.
    serve(
      const StubResponse(
        status: 206,
        body: '',
        contentType: 'text/html; charset=utf-8',
      ),
    );
    await expectLater(
      client.requirePlayable(_id, _file),
      throwsA(isA<NotAFileFinServerResponse>()),
    );

    serve(
      const StubResponse(
        status: 302,
        body: '',
        contentType: 'text/html; charset=utf-8',
        headers: {'location': '/somewhere'},
      ),
    );
    await client.requirePlayable(_id, _file);

    // **300 exactly, and this one is here because it survived.** The guard is
    // `< 300`, and mutating it to `<= 300` killed no test until this case
    // existed: 206 and 302 sit either side of the boundary without touching
    // it. `300 Multiple Choices` is a redirect status, so HTML is Go's own
    // page and not the SPA catch-all — the same class of off-by-one M4.R/T9
    // found inside its own fix.
    serve(
      const StubResponse(
        status: 300,
        body: '',
        contentType: 'text/html; charset=utf-8',
        headers: {'location': '/somewhere'},
      ),
    );
    await client.requirePlayable(_id, _file);
  });

  test('validateStatus stops at 400, on both sides', () async {
    // 399 returns, 400 throws. Anything below 400 is "the server will serve
    // this, possibly after a redirect"; 400 and up is a refusal.
    serve(
      const StubResponse(status: 399, body: '', contentType: 'video/mp4'),
    );
    await client.requirePlayable(_id, _file);

    serve(
      const StubResponse(
        status: 400,
        body: 'bad file index',
        contentType: 'text/plain',
      ),
    );
    await expectLater(
      client.requirePlayable(_id, _file),
      throwsA(isA<BadRequest>()),
    );
  });

  test('404 and 503 keep their own variants', () async {
    serve(
      const StubResponse(status: 404, body: '', contentType: 'text/plain'),
    );
    await expectLater(
      client.requirePlayable(_id, _file),
      throwsA(isA<NotFound>()),
    );

    serve(
      const StubResponse(status: 503, body: '', contentType: 'text/plain'),
    );
    await expectLater(
      client.requirePlayable(_id, _file),
      throwsA(isA<CacheUnavailable>()),
    );
  });

  test('a 401 goes through F3 and the pre-flight is retried once', () async {
    serveLogin(stub, urls);
    await client.login(creds);
    var seen = 0;
    stub.on('HEAD', path, (_) {
      seen++;
      return seen == 1
          ? const StubResponse.unauthorized()
          : const StubResponse(
              status: 307,
              body: '',
              contentType: 'text/html',
              headers: {'location': '/x/hls/index.m3u8'},
            );
    });

    await client.requirePlayable(_id, _file);

    expect(seen, 2);
  });

  test('a malformed media id never reaches the socket', () async {
    await expectLater(
      client.requirePlayable(const MediaId(''), _file),
      throwsA(isA<MalformedIdentifier>()),
    );
    expect(stub.requests, isEmpty);
  });

  test('a cancelled pre-flight is RequestCancelled, not a failure', () async {
    final token = CancelToken();
    stub.on('HEAD', path, (_) {
      token.cancel();
      return null;
    });

    await expectLater(
      client.requirePlayable(_id, _file, cancelToken: token),
      throwsA(isA<RequestCancelled>()),
    );
  });
}
