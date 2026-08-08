import 'dart:typed_data';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/client_harness.dart';
import 'support/stub_server.dart';

/// `GET /api/media/{id}/poster` — the one route that serves bytes rather than
/// JSON, and the one whose 404 is not an error.
void main() {
  late StubServer stub;
  late FileFinClient client;
  late FileFinUrls urls;

  const image = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46];
  const media = MediaId('e4285edb34d5');

  setUp(() async {
    stub = await StubServer.start();
    addTearDown(stub.close);
    urls = FileFinUrls(stub.baseUrl);
    client = ClientHarness.build(stub, urls, InMemorySecretStore()).client;
    addTearDown(client.close);
  });

  test('a 200 returns the bytes exactly as sent', () async {
    stub.on(
      'GET',
      urls.poster(media).path,
      (_) => const StubResponse.binary(image, contentType: 'image/jpeg'),
    );

    final bytes = await client.posterBytes(media);

    expect(bytes, isA<Uint8List>());
    expect(bytes, image);
  });

  test('a 404 is null, because "no poster" is the normal answer', () async {
    // docs/server-api.md: 404 here is what an un-enriched library returns for
    // an item with no poster at all, and it must not surface as an error. The
    // whole point of the nullable return is that the caller cannot confuse it
    // with a failure.
    stub.on(
      'GET',
      urls.poster(media).path,
      (_) => const StubResponse(
        status: 404,
        body: '404 page not found',
        contentType: 'text/plain; charset=utf-8',
      ),
    );

    expect(await client.posterBytes(media), isNull);
  });

  test('the size hint reaches the wire only when asked for', () async {
    // `size` is a hint, not a contract (`media.go:351`): an unknown value and
    // an absent one both serve the base poster. Sending `size=` always would
    // make every request look like a request for a variant.
    stub.on(
      'GET',
      urls.poster(media).path,
      (_) => const StubResponse.binary(image, contentType: 'image/jpeg'),
    );

    await client.posterBytes(media);
    await client.posterBytes(media, size: PosterSize.tile);

    expect(stub.requests.first.query, isEmpty);
    expect(stub.requests.last.query, {'size': 'tile'});
  });

  test('a non-image content type is fine — ServeFile follows the file', () {
    // The server serves whatever the file is through `http.ServeFile`, so the
    // content type is the file's and this client has no business insisting on
    // `image/*`. A poster stored as a WebP, a PNG or with no type at all is
    // still a poster.
    stub.on(
      'GET',
      urls.poster(media).path,
      (_) => const StubResponse.binary(
        image,
        contentType: 'application/octet-stream',
      ),
    );

    expect(client.posterBytes(media), completion(image));
  });

  test('an HTML body is NOT a poster, it is the SPA catch-all', () async {
    // Same reasoning as F1. This server answers an unmatched `/api/*` path
    // with `200 text/html` (`server.go:352`), so a `200` whose body is HTML
    // means the route is gone or the address is not FileFin — and handing
    // those bytes to an ImageProvider would show a broken image instead of
    // saying what happened.
    stub.on(
      'GET',
      urls.poster(media).path,
      (_) => const StubResponse(
        status: 200,
        body: '<!doctype html><html><body>FileFin</body></html>',
        contentType: 'text/html; charset=utf-8',
      ),
    );

    await expectLater(
      client.posterBytes(media),
      throwsA(isA<NotAFileFinServerResponse>()),
    );
  });

  test('a 401 is renewed and replayed transparently (F3)', () async {
    serveLogin(stub, urls);
    await client.login(creds);
    var protectedHits = 0;
    stub.on('GET', urls.poster(media).path, (request) {
      protectedHits += 1;
      return request.cookie == 'filefin_session=sess-2'
          ? const StubResponse.binary(image, contentType: 'image/jpeg')
          : const StubResponse.unauthorized();
    });

    expect(await client.posterBytes(media), image);
    expect(protectedHits, 2, reason: 'the 401 and the replay');
  });

  test('a cancelled request is RequestCancelled, not a null poster', () async {
    // The difference matters to a scrolling grid: a tile that leaves the
    // viewport cancels, and reporting that as "this item has no poster" would
    // cache a placeholder over an item that has one.
    final token = CancelToken();
    stub.on('GET', urls.poster(media).path, (_) {
      token.cancel();
      return null;
    });

    await expectLater(
      client.posterBytes(media, cancelToken: token),
      throwsA(isA<RequestCancelled>()),
    );
  });

  test('an empty id is a failed Future, never a synchronous throw', () async {
    // `MediaSummary.id` defaults to `MediaId('')` (§8's tolerant decoding), so
    // a payload with a missing id produces one — and a grid building 5000
    // tiles must not have to wrap a call in `try` as well as `await`.
    final future = client.posterBytes(const MediaId(''));

    await expectLater(future, throwsA(isA<MalformedIdentifier>()));
    expect(stub.requests, isEmpty, reason: 'no request was made');
  });

  test('a 503 stays a CacheUnavailable rather than collapsing to null', () {
    // Only 404 means "no poster". Folding any other failure into null would
    // tell a user their library has no artwork when the server is rebuilding.
    stub.on(
      'GET',
      urls.poster(media).path,
      (_) => const StubResponse(
        status: 503,
        body: 'cache unavailable',
        contentType: 'text/plain; charset=utf-8',
      ),
    );

    expect(
      client.posterBytes(media),
      throwsA(isA<CacheUnavailable>()),
    );
  });
}
