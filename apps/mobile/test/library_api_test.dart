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

  setUpAll(() {
    // Restoring real sockets. `_MockHttpOverrides` is a plain static
    // assignment in flutter_test's binding, so this is a supported seam rather
    // than a trick — but it must be undone, because leaving it null in a suite
    // that runs alongside widget tests would let a forgotten request out.
    HttpOverrides.global = null;
  });

  setUp(() async {
    seen.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final query = request.uri.query;
        seen.add(
          '${request.method} ${request.uri.path}'
          '${query.isEmpty ? '' : '?$query'}',
        );
        final response = request.response;
        if (request.uri.path.endsWith('/progress')) {
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
    expect(seen, ['POST /api/login']);
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

    expect(seen, ['POST /api/media/e4285edb34d5/progress']);
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
  if (path.endsWith('/media')) {
    return [
      {'id': 'e4285edb34d5', 'title': 'Direct Play Movie', 'year': 2020},
    ];
  }
  return {'id': 'e4285edb34d5', 'title': 'Direct Play Movie', 'year': 2020};
}
