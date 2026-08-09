import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// `FileFinLibraryApi` is a delegation, so what is worth testing is that every
/// method reaches the right route with the right method — not that dio works.
///
/// Against a **real `dart:io` `HttpServer`**, not a mock adapter. That is the
/// same reasoning `filefin_api`'s `StubServer` records: what a mock would skip
/// is the layer where the cookie jar, the interceptor order and the headers
/// live. `flutter_test`'s binding installs an `HttpOverrides` that answers 400
/// for everything (measured at M3.0), so `setUpAll` puts it back — and every
/// body here is a plain `test()`, which does NOT run under `FakeAsync`, so a
/// real socket completes normally.
void main() {
  late HttpServer server;
  late FileFinLibraryApi api;
  final seen = <String>[];

  /// Paths the stub answers `401` for, once each.
  ///
  /// One-shot rather than sticky, because what F3 is being asked to prove is
  /// that the SECOND attempt succeeds: a permanently-401 route would make
  /// "renewed and retried" indistinguishable from "gave up".
  final unauthorized = <String>{};

  setUpAll(() {
    // Restoring real sockets. `_MockHttpOverrides` is a plain static
    // assignment in flutter_test's binding, so this is a supported seam rather
    // than a trick — but it must be undone, because leaving it null in a suite
    // that runs alongside widget tests would let a forgotten request out.
    HttpOverrides.global = null;
  });

  setUp(() async {
    seen.clear();
    unauthorized.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final query = request.uri.query;
        // THE BODY IS PART OF THE RECORD, and its absence was a whole missing
        // layer. Three of F10's four writes differ from each other only in what
        // they send — `{"watched": false}` and `{"watched": true}` are the same
        // verb on the same path — so a harness that recorded method and path
        // alone could not tell *mark as unwatched* from *mark as watched*.
        // Measured: `watched: watched` rewritten to `watched: true` in
        // `library_api.dart` passed every test in this file.
        final body = await utf8.decoder.bind(request).join();
        seen.add(
          '${request.method} ${request.uri.path}'
          '${query.isEmpty ? '' : '?$query'}'
          '${body.isEmpty ? '' : ' $body'}',
        );
        final response = request.response;
        if (unauthorized.remove(request.uri.path)) {
          response.statusCode = 401;
          await response.close();
          return;
        }
        if (request.uri.path.endsWith('/progress') ||
            request.uri.path.endsWith('/favorite') ||
            request.uri.path.endsWith('/rating') ||
            request.uri.path.endsWith('/watched')) {
          response.statusCode = 204;
        } else if (request.uri.path.contains('/sub/')) {
          response.headers.contentType = ContentType('text', 'vtt');
          response.write('WEBVTT\n\n00:00.000 --> 00:02.000\nHello\n');
        } else if (request.uri.path.endsWith('/poster')) {
          response.headers.contentType = ContentType('image', 'jpeg');
          response.add([1, 2, 3]);
        } else {
          response.headers.contentType = ContentType('application', 'json');
          if (request.uri.path.endsWith('/api/login')) {
            // A login with no `Set-Cookie` is a MalformedResponse, not a
            // success (`session.dart:116`). The real server sets one, so a
            // fake that forgets is testing a case that cannot happen.
            response.headers.add(
              'set-cookie',
              'filefin_session=sess-1; Path=/; HttpOnly',
            );
          }
          response.write(jsonEncode(_bodyFor(request.uri.path)));
        }
        await response.close();
      }),
    );
    final client = FileFinClient.forServer(
      server: const ServerId('home'),
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      secrets: InMemorySecretStore(),
    );
    api = FileFinLibraryApi(client);
    addTearDown(() async {
      api.close();
      await server.close(force: true);
    });
  });

  test('it names the server it talks to', () {
    expect(api.server, const ServerId('home'));
  });

  test('probeServer reaches GET /api/state', () async {
    expect(await api.probeServer(), isA<FileFinServer>());
    expect(seen, ['GET /api/state']);
  });

  test('login POSTs /api/login', () async {
    final result = await api.login(
      const Credentials(username: 'sam', password: 'hunter2'),
    );

    expect(result.user, 'sam');
    expect(seen, ['POST /api/login {"username":"sam","password":"hunter2"}']);
  });

  test('categories reaches GET /api/categories', () async {
    final categories = await api.categories();

    expect(categories.map((c) => c.leaf), ['Films']);
    expect(seen, ['GET /api/categories']);
  });

  test('categoryMedia puts the id in the path, not a query', () async {
    // The route is `/api/category/{id}/media`. A client that sent
    // `?id=` would be answered by the SPA catch-all with `200 text/html`,
    // which is a success that is not one.
    final media = await api.categoryMedia(const CategoryId(1));

    expect(media.single.title, 'Direct Play Movie');
    expect(seen, ['GET /api/category/1/media']);
  });

  test('mediaDetail reaches GET /api/media/{id}', () async {
    final detail = await api.mediaDetail(const MediaId('e4285edb34d5'));

    expect(detail.title, 'Direct Play Movie');
    expect(seen, ['GET /api/media/e4285edb34d5']);
  });

  test('posterBytes reaches the poster route and returns the bytes', () async {
    final bytes = await api.posterBytes(const MediaId('e4285edb34d5'));

    expect(bytes, [1, 2, 3]);
    expect(seen, ['GET /api/media/e4285edb34d5/poster']);
  });

  test('the size hint is forwarded, and only when given', () async {
    await api.posterBytes(const MediaId('abc'));
    await api.posterBytes(const MediaId('abc'), size: PosterSize.detail);

    expect(seen, [
      'GET /api/media/abc/poster',
      'GET /api/media/abc/poster?size=detail',
    ]);
  });

  test('a cancel token reaches the wire and stops the request', () async {
    // NF5: every in-flight operation is cancellable. A port that accepted a
    // token and dropped it would look identical from the call site and leave a
    // scrolled-away tile's request running.
    final token = CancelToken()..cancel();

    await expectLater(
      api.categories(cancelToken: token),
      throwsA(isA<RequestCancelled>()),
    );
    expect(seen, isEmpty);
  });

  test('me reaches GET /api/me', () async {
    expect((await api.me()).user, 'sam');
    expect(seen, ['GET /api/me']);
  });

  test('postProgress POSTs the report to the progress route', () async {
    await api.postProgress(
      const MediaId('e4285edb34d5'),
      const ProgressReport(
        file: FileIndex(1),
        position: 12,
        duration: 100,
        event: ProgressEvent.seek,
      ),
    );

    const body = '{"file":1,"position":12.0,"duration":100.0,"event":"seek"}';
    expect(seen, ['POST /api/media/e4285edb34d5/progress $body']);
  });

  test('home reaches GET /api/home', () async {
    await api.home();

    expect(seen, ['GET /api/home']);
  });

  test('search puts BOTH the query and the scope on the wire', () async {
    // A port that dropped `field` would still return plausible results — an
    // unrecognised scope degrades to `all` upstream (`db/search.go:74`) — so
    // the query string is the only thing that can tell a forwarded selector
    // from a discarded one.
    await api.search('Kurosawa', field: SearchField.director);

    expect(seen, ['GET /api/search?q=Kurosawa&field=director']);
  });

  test('setFavorite POSTs the favorite route, and BOTH values', () async {
    // Both arms, because the route and the verb are identical for the two and
    // the body is the only thing that differs. `favorite: favorite` rewritten
    // to `favorite: true` in the port passed every assertion in this file
    // before the harness read a body — *remove from favourites* favourited.
    await api.setFavorite(const MediaId('e4285edb34d5'), favorite: true);
    await api.setFavorite(const MediaId('e4285edb34d5'), favorite: false);

    expect(seen, [
      'POST /api/media/e4285edb34d5/favorite {"favorite":true}',
      'POST /api/media/e4285edb34d5/favorite {"favorite":false}',
    ]);
  });

  test('setRating POSTs the rating route, carrying the number', () async {
    // 0 as well as 7: 0 is how the server clears a rating, so a port that sent
    // a constant would be indistinguishable from one that worked at 7 alone.
    await api.setRating(const MediaId('e4285edb34d5'), rating: 7);
    await api.setRating(const MediaId('e4285edb34d5'), rating: 0);

    expect(seen, [
      'POST /api/media/e4285edb34d5/rating {"rating":7}',
      'POST /api/media/e4285edb34d5/rating {"rating":0}',
    ]);
  });

  test('the port does not soften the rating guard', () async {
    // The delegation is thin on purpose: the range check lives in
    // `filefin_api` and a port that caught or clamped it would be a second
    // place for the rule to live and disagree.
    await expectLater(
      api.setRating(const MediaId('e4285edb34d5'), rating: 11),
      throwsA(isA<RangeError>()),
    );
    expect(seen, isEmpty);
  });

  test('setWatched POSTs and clearWatched DELETEs, on ONE path', () async {
    // The tripwire, at the port. These are two different operations against
    // the same URL (M6.0/E-5): the POST keeps the resume pointer and the
    // DELETE drops it, so a port that routed both through one method would
    // erase a position every time a user un-watches something — and the path
    // alone cannot tell them apart.
    //
    // Both POST bodies, because the path cannot tell those apart either:
    // `watched: watched` rewritten to `watched: true` survived this whole file
    // until the harness above started reading a body, which means *mark as
    // unwatched* marked watched and nothing here objected.
    await api.setWatched(const MediaId('e4285edb34d5'), watched: false);
    await api.setWatched(const MediaId('e4285edb34d5'), watched: true);
    await api.clearWatched(const MediaId('e4285edb34d5'));

    expect(seen, [
      'POST /api/media/e4285edb34d5/watched {"watched":false}',
      'POST /api/media/e4285edb34d5/watched {"watched":true}',
      // The DELETE carries NO body: one with `{"watched": false}` in it would
      // be `setWatched` wearing the wrong verb.
      'DELETE /api/media/e4285edb34d5/watched',
    ]);
  });

  test('subtitleText reaches the sidecar route and returns WebVTT', () async {
    final text = await api.subtitleText(
      const MediaId('e4285edb34d5'),
      const FileIndex(0),
      const SubtitleIndex(1),
    );

    expect(text, startsWith('WEBVTT'));
    expect(seen, ['GET /api/media/e4285edb34d5/file/0/sub/1']);
  });

  test(
    'playbackHeaders proves the session first, then hands the cookie over',
    () async {
      await api.login(const Credentials(username: 'sam', password: 'hunter2'));
      seen.clear();

      final headers = await api.playbackHeaders();

      // The `me` is what makes F3 renew a dead session before libmpv — which
      // cannot see a 401 — is handed a cookie.
      expect(seen, ['GET /api/me']);
      expect(headers.headers, {'Cookie': 'filefin_session=sess-1'});
    },
  );

  test('requirePlayable HEADs the file route, and nothing else', () async {
    // The method matters as much as the path. A `GET` here would move media
    // bytes on the direct-play arm and 81 bytes of Go's redirect HTML on the
    // other (M5.0/E-A); a mismatched method would also be answered `200
    // text/html` by the SPA catch-all rather than with a 405, so it would look
    // like a success.
    await api.requirePlayable(
      const MediaId('e4285edb34d5'),
      const FileIndex(0),
    );

    expect(seen, ['HEAD /api/media/e4285edb34d5/file/0']);
  });

  test('fileUrl and subtitleUrl are absolute and correctly shaped', () {
    expect(
      api.fileUrl(const MediaId('abc'), const FileIndex(2)).path,
      '/api/media/abc/file/2',
    );
    expect(
      api
          .subtitleUrl(
            const MediaId('abc'),
            const FileIndex(2),
            const SubtitleIndex(3),
          )
          .path,
      '/api/media/abc/file/2/sub/3',
    );
    // Built, not requested: handing libmpv a URL is not the same as fetching
    // it, and nothing here should have touched the socket.
    expect(seen, isEmpty);
  });

  test('playbackTransport reports what libmpv could verify', () {
    // The stub server is plain http, so this is the plainHttp arm. The pinned
    // and OS-trusted arms are `filefin_api`'s to prove — they depend on the
    // pin, which lives there.
    expect(api.playbackTransport(), PlaybackTransport.plainHttp);
  });

  test('close releases the client', () async {
    api.close();

    await expectLater(api.categories(), throwsA(isA<FileFinApiException>()));
  });
}

Object _bodyFor(String path) {
  if (path.endsWith('/api/state')) {
    return {'needsSetup': false, 'version': '0.20.3'};
  }
  if (path.endsWith('/api/login') || path.endsWith('/api/me')) {
    return {'user': 'sam', 'admin': false};
  }
  if (path.endsWith('/api/categories')) {
    return [
      {'id': 1, 'name': 'Films', 'leaf': 'Films', 'parentId': 0},
    ];
  }
  if (path.endsWith('/api/search')) {
    return [
      {'id': 'e4285edb34d5', 'title': 'Direct Play Movie', 'year': 2020},
    ];
  }
  if (path.endsWith('/api/home')) {
    return {
      'continue': <Object?>[],
      'favorites': <Object?>[],
      'completed': <Object?>[],
    };
  }
  if (path.endsWith('/media')) {
    return [
      {'id': 'e4285edb34d5', 'title': 'Direct Play Movie', 'year': 2020},
    ];
  }
  return {'id': 'e4285edb34d5', 'title': 'Direct Play Movie', 'year': 2020};
}
