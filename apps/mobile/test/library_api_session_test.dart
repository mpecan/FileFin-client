import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter_test/flutter_test.dart';

/// The three session routes of `FileFinLibraryApi`: login, logout and F2's
/// cold-start restore.
///
/// Split from `library_api_test.dart` at M7.3 for `just file-size`, over the
/// same stub server — what is worth testing is that each reaches the right
/// route with the right METHOD, not that dio works.
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

  test('logout POSTs /api/logout', () async {
    // The verb is the assertion. A `getUri` here would be answered `200
    // text/html` by the SPA catch-all rather than with a 405 — measured live
    // on this exact route (`probe_and_login_test.dart:101`) — so the session
    // would survive a sign-out and nothing would say so.
    await api.login(const Credentials(username: 'sam', password: 'hunter2'));
    seen.clear();

    await api.logout();

    expect(seen, ['POST /api/logout']);
  });

  group('restore — F2 s cold start, and F3 s renewal behind it', () {
    test('a live stored session is proved with GET /api/me', () async {
      await api.login(const Credentials(username: 'sam', password: 'hunter2'));
      seen.clear();

      await api.restore();

      expect(seen, ['GET /api/me']);
    });

    test('a session the server forgot is renewed silently', () async {
      // L1 is routine, so this is the ordinary cold start rather than an edge
      // case: the stored cookie is dead, `restore()` gets a 401, and F3's
      // renewal signs in again from the stored password with no prompt. The
      // POST is the whole assertion — without it the app would land on the
      // sign-in screen every time the server had restarted.
      final client = FileFinClient.forServer(
        server: const ServerId('home'),
        baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
        secrets: InMemorySecretStore(),
        // The username is `settings.json`'s `lastUser`. Without it there is
        // nothing silent to do, which is the third case below.
        username: 'sam',
      );
      final restoring = FileFinLibraryApi(client);
      addTearDown(restoring.close);
      await restoring.login(
        const Credentials(username: 'sam', password: 'hunter2'),
      );
      unauthorized.add('/api/me');
      seen.clear();

      await restoring.restore();

      expect(seen, [
        'GET /api/me',
        'POST /api/login {"username":"sam","password":"hunter2"}',
      ]);
    });

    test('nothing stored at all is a SessionExpired, and no login', () async {
      // A first launch, or the launch after a sign-out. There is no password
      // to renew from, so guessing is not an option and the caller prompts.
      await expectLater(api.restore(), throwsA(isA<SessionExpired>()));
      expect(seen, isEmpty);
    });
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
