/// F10's four writes, against a real socket.
///
/// Every route is registered by `urls.X(...).path`, never a literal, so
/// renaming one in `ApiPaths` cannot leave a stub answering the old path — and
/// every registration names its METHOD, which is what makes the POST/DELETE
/// distinction below assertable at all.
library;

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/client_harness.dart';
import 'support/stub_server.dart';

const _id = MediaId('e4285edb34d5');

StubResponse _noContent(StubRequest _) =>
    const StubResponse(status: 204, body: '', contentType: 'text/plain');

StubResponse _status(int status, String body) =>
    StubResponse(status: status, body: body, contentType: 'text/plain');

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

  group('setFavorite', () {
    test('POSTs {"favorite": true} and accepts a 204', () async {
      stub.on('POST', urls.favorite(_id).path, _noContent);
      await client.setFavorite(_id, favorite: true);
      final sent = stub.requests.single;
      expect(sent.method, 'POST');
      expect(sent.path, urls.favorite(_id).path);
      expect(sent.headers['content-type'], contains('application/json'));
      expect(sent.body, '{"favorite":true}');
    });

    test('un-favouriting is a different BODY, not a different route', () async {
      stub.on('POST', urls.favorite(_id).path, _noContent);
      await client.setFavorite(_id, favorite: false);
      expect(stub.requests.single.body, '{"favorite":false}');
      expect(stub.requests.single.method, 'POST');
    });
  });

  group('setRating — the guard, on both sides of both boundaries', () {
    for (final rating in [0, 1, 10]) {
      test('$rating is sent as {"rating": $rating}', () async {
        stub.on('POST', urls.rating(_id).path, _noContent);
        await client.setRating(_id, rating: rating);
        expect(stub.requests.single.body, '{"rating":$rating}');
        expect(stub.requests.single.method, 'POST');
      });
    }

    test('0 is sent, not omitted — 0 is how the server CLEARS a rating', () {
      stub.on('POST', urls.rating(_id).path, _noContent);
      return client.setRating(_id, rating: 0).then((_) {
        expect(stub.requests.single.body, contains('"rating":0'));
      });
    });

    for (final rating in [-1, 11, 99, -2147483648]) {
      test('$rating is refused BEFORE any socket opens', () async {
        stub.on('POST', urls.rating(_id).path, _noContent);
        await expectLater(
          client.setRating(_id, rating: rating),
          // The CONTENTS, not just the type. A `RangeError` that named the
          // wrong value or the wrong bound would still satisfy `isA`, and the
          // whole reason this is a `RangeError` rather than a `BadRequest` is
          // that it says which value and which bound.
          throwsA(
            isA<RangeError>()
                .having((e) => e.invalidValue, 'invalidValue', rating)
                .having((e) => e.start, 'start', 0)
                .having((e) => e.end, 'end', 10)
                .having((e) => e.name, 'name', 'rating'),
          ),
        );
        // The load-bearing half. A guard that threw after the request was on
        // the wire would still pass a `throwsA`, and the server would have
        // answered `400 rating out of range` — which arrives here as
        // `BadRequest`, whose message says the item changed on the server.
        expect(stub.requests, isEmpty);
      });
    }
  });

  group('the two un-watch operations are not the same operation', () {
    test('setWatched POSTs a body and keeps the pointer', () async {
      stub.on('POST', urls.watched(_id).path, _noContent);
      await client.setWatched(_id, watched: true);
      expect(stub.requests.single.method, 'POST');
      expect(stub.requests.single.body, '{"watched":true}');
    });

    test('clearWatched DELETEs, and carries no body at all', () async {
      stub.on('DELETE', urls.watched(_id).path, _noContent);
      await client.clearWatched(_id);
      expect(stub.requests.single.method, 'DELETE');
      expect(stub.requests.single.body, isEmpty);
    });

    test(
      'THE TRIPWIRE: POST false and DELETE differ in method, on one path',
      () async {
        // M6.0/E-5 measured what the difference costs: against v0.20.3, on a
        // two-file show with the pointer at file 0 at 45 seconds,
        // `POST {"watched": false}` put the item back in `continue` STILL at
        // 45 seconds while `DELETE` left it in no home row with the pointer
        // gone. A client that collapsed the two into one boolean would erase
        // the resume position of every item a user un-watches.
        stub
          ..on('POST', urls.watched(_id).path, _noContent)
          ..on('DELETE', urls.watched(_id).path, _noContent);
        await client.setWatched(_id, watched: false);
        await client.clearWatched(_id);
        expect(stub.requests.map((r) => r.method).toList(), [
          'POST',
          'DELETE',
        ]);
        expect(stub.requests.map((r) => r.path).toSet(), {
          urls.watched(_id).path,
        });
        expect(stub.requests.map((r) => r.body).toList(), [
          '{"watched":false}',
          '',
        ]);
      },
    );
  });

  group('every write speaks the one error vocabulary', () {
    test('a 404 on an unknown id is NotFound, on all four', () async {
      stub
        ..on('POST', urls.favorite(_id).path, (_) => _status(404, 'not found'))
        ..on('POST', urls.rating(_id).path, (_) => _status(404, 'not found'))
        ..on('POST', urls.watched(_id).path, (_) => _status(404, 'not found'))
        ..on('DELETE', urls.watched(_id).path, (_) => _status(404, 'nope'));
      await expectLater(
        client.setFavorite(_id, favorite: true),
        throwsA(isA<NotFound>()),
      );
      await expectLater(
        client.setRating(_id, rating: 5),
        throwsA(isA<NotFound>()),
      );
      await expectLater(
        client.setWatched(_id, watched: true),
        throwsA(isA<NotFound>()),
      );
      await expectLater(client.clearWatched(_id), throwsA(isA<NotFound>()));
    });

    test('a 503 is CacheUnavailable, never "you have no item"', () async {
      stub.on(
        'DELETE',
        urls.watched(_id).path,
        (_) => _status(503, 'cache unavailable'),
      );
      await expectLater(
        client.clearWatched(_id),
        throwsA(isA<CacheUnavailable>()),
      );
    });

    test('a 400 from the server is BadRequest', () async {
      // Reachable even with the local guard in place: `decodeJSON` runs before
      // the folder lookup, so a body the server cannot read is a 400 whatever
      // the id (measured, M6.0/E-6).
      stub.on(
        'POST',
        urls.favorite(_id).path,
        (_) => _status(400, 'bad request'),
      );
      await expectLater(
        client.setFavorite(_id, favorite: true),
        throwsA(isA<BadRequest>()),
      );
    });

    group('the SPA catch-all is not a successful write (M7.8)', () {
      // **A write against a route that does not exist SUCCEEDED until M7.8.**
      // The server registers its SPA catch-all outside the route table
      // (`server.go:352`), so an unmatched `/api/*` path answers `200 text/html`
      // with `index.html` rather than a 404 or a 405 — and `_sendJson` and
      // `_sendDelete` looked only at the status. Every F10 write then reported
      // success to a screen that had already drawn the change optimistically.
      //
      // **F11 makes it likelier rather than rarer**, which is why it was
      // paid here: a user who can save several servers can save a base URL
      // with a stray path on it, and after that nothing they tap is stored.
      //
      // `StubServer` answers an unregistered path exactly the way the real
      // server does, so registering nothing IS the case under test.
      test('every POST refuses HTML', () async {
        for (final call in <(String, Future<void> Function())>[
          ('favorite', () => client.setFavorite(_id, favorite: true)),
          ('rating', () => client.setRating(_id, rating: 5)),
          ('watched', () => client.setWatched(_id, watched: true)),
          (
            'progress',
            () => client.postProgress(
              _id,
              const ProgressReport(
                file: FileIndex(0),
                position: 1,
                duration: 2,
              ),
            ),
          ),
        ]) {
          await expectLater(
            call.$2(),
            throwsA(isA<NotAFileFinServerResponse>()),
            reason: '${call.$1} read the catch-all as a successful write',
          );
        }
      });

      test('the DELETE refuses HTML too', () async {
        // Its own case, because it is its own helper: `_sendDelete` exists
        // because the VERB is what distinguishes the two un-watch operations,
        // and a fix applied to `_sendJson` alone would leave this one silent.
        await expectLater(
          client.clearWatched(_id),
          throwsA(isA<NotAFileFinServerResponse>()),
        );
      });

      test('a real 204 with no content type is still a success', () async {
        // The other direction, and it is the one that would break users: these
        // routes answer `204` with no body and no `Content-Type` at all, so a
        // check that demanded JSON would refuse every legitimate write.
        stub.on('POST', urls.favorite(_id).path, _noContent);
        await client.setFavorite(_id, favorite: true);
        expect(stub.requests.single.method, 'POST');
      });
    });

    test('an unusable media id is a failed Future, not a raw Error', () async {
      // `MediaId('')` is the models' own default, so a payload with a missing
      // `id` produces one, and `Uri` would delete the empty segment and address
      // a shorter route the SPA catch-all answers `200 text/html`.
      for (final call in <Future<void> Function()>[
        () => client.setFavorite(const MediaId(''), favorite: true),
        () => client.setRating(const MediaId(''), rating: 5),
        () => client.setWatched(const MediaId(''), watched: true),
        () => client.clearWatched(const MediaId('')),
      ]) {
        await expectLater(call(), throwsA(isA<MalformedIdentifier>()));
      }
      expect(stub.requests, isEmpty);
    });
  });

  group('F3 covers the DELETE too', () {
    test('a 401 re-authenticates and replays with the NEW cookie', () async {
      // `_sendDelete` is a new transport path, so the retry has to be proven
      // over it rather than inherited from `_send`'s tests.
      serveLogin(stub, urls);
      final harness = ClientHarness.build(stub, urls, InMemorySecretStore());
      addTearDown(harness.client.close);
      await harness.client.login(creds);
      stub.on(
        'DELETE',
        urls.watched(_id).path,
        (r) => r.cookie == 'filefin_session=sess-2'
            ? _noContent(r)
            : const StubResponse.unauthorized(),
      );
      await harness.client.clearWatched(_id);
      expect(harness.logins.count, 2);
      expect(stub.countFor(urls.watched(_id).path), 2);
    });
  });
}
