import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/client_harness.dart';
import 'support/fixtures.dart';
import 'support/stub_server.dart';

const _id = MediaId('e4285edb34d5');

void main() {
  late StubServer stub;
  late FileFinUrls urls;
  late FileFinClient client;
  late InMemorySecretStore secrets;

  setUp(() async {
    stub = await StubServer.start();
    addTearDown(stub.close);
    urls = FileFinUrls(stub.baseUrl);
    secrets = InMemorySecretStore();
    client = ClientHarness.build(stub, urls, secrets).client;
    addTearDown(client.close);
  });

  /// Signs in for real through the stub, so the jar holds a session cookie.
  ///
  /// `serveLogin` issues `sess-1` for the first login, which is what the
  /// assertions below name.
  Future<void> signIn() async {
    serveLogin(stub, urls);
    await client.login(creds);
  }

  group('postProgress (F9)', () {
    test('POSTs the report as JSON and accepts a 204', () async {
      stub.on(
        'POST',
        urls.progress(_id).path,
        (_) => const StubResponse(
          status: 204,
          body: '',
          contentType: 'text/plain',
        ),
      );
      await client.postProgress(
        _id,
        const ProgressReport(
          file: FileIndex(1),
          position: 12.5,
          duration: 100,
          event: ProgressEvent.pause,
        ),
      );
      final sent = stub.requests.last;
      expect(sent.method, 'POST');
      expect(sent.headers['content-type'], contains('application/json'));
      // Field names and the event vocabulary are the server's, so they are
      // asserted literally rather than through a round-trip that would agree
      // with whatever we happened to write.
      expect(
        sent.body,
        '{"file":1,"position":12.5,"duration":100.0,"event":"pause"}',
      );
    });

    test('a 400 is BadRequest, and BadRequest is not retryable', () async {
      // `bad file index` — captured from the real binary at v0.20.3. Retrying
      // it always fails, which is why it is its own variant and not a
      // ServerFailure.
      stub.on(
        'POST',
        urls.progress(_id).path,
        (_) => const StubResponse(
          status: 400,
          body: 'bad file index',
          contentType: 'text/plain; charset=utf-8',
        ),
      );
      await expectLater(
        client.postProgress(
          _id,
          const ProgressReport(
            file: FileIndex(99),
            position: 1,
            duration: 10,
          ),
        ),
        throwsA(
          isA<BadRequest>()
              .having((e) => e.body, 'body', 'bad file index')
              .having(
                (e) => e.requested,
                'requested',
                urls.progress(_id),
              ),
        ),
      );
    });

    test('a malformed id never reaches the socket', () async {
      await expectLater(
        client.postProgress(
          const MediaId(''),
          const ProgressReport(file: FileIndex(0), position: 1, duration: 10),
        ),
        throwsA(isA<MalformedIdentifier>()),
      );
      expect(stub.requests, isEmpty);
    });

    test('a 401 still routes through F3 and retries once', () async {
      await signIn();
      var seen = 0;
      stub.on('POST', urls.progress(_id).path, (_) {
        seen++;
        return seen == 1
            ? const StubResponse.unauthorized()
            : const StubResponse(
                status: 204,
                body: '',
                contentType: 'text/plain',
              );
      });
      await client.postProgress(
        _id,
        const ProgressReport(file: FileIndex(0), position: 1, duration: 10),
      );
      expect(seen, 2);
    });
  });

  group('subtitleText (F7)', () {
    test('returns the WebVTT body verbatim', () async {
      final url = urls.subtitle(
        _id,
        const FileIndex(0),
        const SubtitleIndex(0),
      );
      stub.on(
        'GET',
        url.path,
        (_) => StubResponse(
          status: 200,
          body: fixtureText('subtitle.vtt'),
          // The real server answers `text/vtt; charset=utf-8` — measured live
          // at v0.20.3. So this route must NOT go through the JSON media-type
          // check, or every subtitle would read as "not a FileFin server".
          contentType: 'text/vtt; charset=utf-8',
        ),
      );
      final text = await client.subtitleText(
        _id,
        const FileIndex(0),
        const SubtitleIndex(0),
      );
      expect(text, startsWith('WEBVTT'));
      expect(text, contains('Hello fixture'));
    });

    test('refuses the SPA catch-all rather than handing back index.html', () {
      // Nothing is registered, so the stub answers 200 text/html exactly as
      // the real server does for a route that moved.
      expect(
        client.subtitleText(_id, const FileIndex(0), const SubtitleIndex(0)),
        throwsA(isA<NotAFileFinServerResponse>()),
      );
    });

    test('a 404 is NotFound, not an empty string', () async {
      final url = urls.subtitle(
        _id,
        const FileIndex(0),
        const SubtitleIndex(9),
      );
      stub.on(
        'GET',
        url.path,
        (_) => const StubResponse(
          status: 404,
          body: '404 page not found',
          contentType: 'text/plain; charset=utf-8',
        ),
      );
      await expectLater(
        client.subtitleText(_id, const FileIndex(0), const SubtitleIndex(9)),
        throwsA(isA<NotFound>()),
      );
    });

    test('a malformed id never reaches the socket', () async {
      await expectLater(
        client.subtitleText(
          const MediaId(''),
          const FileIndex(0),
          const SubtitleIndex(0),
        ),
        throwsA(isA<MalformedIdentifier>()),
      );
      expect(stub.requests, isEmpty);
    });
  });

  group('playbackHeaders — the cookie libmpv is handed', () {
    test('makes a live authenticated call FIRST, then reads the jar', () async {
      await signIn();
      stub.on(
        'GET',
        urls.me.path,
        (_) => StubResponse(
          status: 200,
          body: fixtureText('me.json'),
          contentType: 'application/json',
        ),
      );
      final headers = await client.playbackHeaders();
      // The `me()` is not decoration: libmpv cannot see a 401, so the session
      // has to be proven alive by the layer that can, immediately before the
      // cookie leaves this package.
      expect(stub.requests.map((r) => r.path), contains(urls.me.path));
      expect(headers.headers, {'Cookie': '$sessionCookieName=sess-1'});
    });

    test('never prints the cookie (§9)', () async {
      await signIn();
      stub.on(
        'GET',
        urls.me.path,
        (_) => StubResponse(
          status: 200,
          body: fixtureText('me.json'),
          contentType: 'application/json',
        ),
      );
      final headers = await client.playbackHeaders();
      expect(headers.toString(), isNot(contains('sess-1')));
      expect(headers.toString(), contains('redacted'));
      expect('$headers', isNot(contains('sess-1')));
    });

    test('a dead session that cannot be renewed is SessionExpired', () async {
      stub.on(
        'GET',
        urls.me.path,
        (_) => const StubResponse.unauthorized(),
      );
      await expectLater(
        client.playbackHeaders(),
        throwsA(isA<SessionExpired>()),
      );
    });

    test(
      'a 200 from me() with no cookie in the jar is SessionExpired',
      () async {
        // The server can answer `me` from a session it holds while our jar has
        // nothing to hand libmpv — handing over an empty cookie would produce a
        // 401 inside mpv, which surfaces as "failed to open" and nothing else.
        stub.on(
          'GET',
          urls.me.path,
          (_) => StubResponse(
            status: 200,
            body: fixtureText('me.json'),
            contentType: 'application/json',
          ),
        );
        await expectLater(
          client.playbackHeaders(),
          throwsA(isA<SessionExpired>()),
        );
      },
    );
  });

  group('the URLs handed to libmpv', () {
    test('fileUrl and subtitleUrl are absolute and go through _uri', () {
      expect(
        client.fileUrl(_id, const FileIndex(2)),
        urls.file(_id, const FileIndex(2)),
      );
      expect(
        client.subtitleUrl(_id, const FileIndex(2), const SubtitleIndex(1)),
        urls.subtitle(_id, const FileIndex(2), const SubtitleIndex(1)),
      );
    });

    test('a malformed id is our error, not a raw ArgumentError', () {
      expect(
        () => client.fileUrl(const MediaId(''), const FileIndex(0)),
        throwsA(isA<MalformedIdentifier>()),
      );
      expect(
        () => client.subtitleUrl(
          const MediaId('.'),
          const FileIndex(0),
          const SubtitleIndex(0),
        ),
        throwsA(isA<MalformedIdentifier>()),
      );
    });
  });

  group('playbackTransport — what libmpv would be able to verify', () {
    FileFinClient clientFor(Uri base, {CertificateFingerprint? pin}) {
      final c = FileFinClient.forServer(
        server: serverId,
        baseUrl: base,
        secrets: InMemorySecretStore(),
        pin: pin,
      );
      addTearDown(c.close);
      return c;
    }

    final fingerprint = CertificateFingerprint.parse(
      'aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99:'
      'aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99',
    );

    test('http is plainHttp', () {
      expect(
        clientFor(Uri.parse('http://nas.local:8099')).playbackTransport(),
        PlaybackTransport.plainHttp,
      );
    });

    test('https with no pin is osTrustedTls', () {
      expect(
        clientFor(Uri.parse('https://nas.local')).playbackTransport(),
        PlaybackTransport.osTrustedTls,
      );
    });

    test('https with a pin is pinnedTls — the case libmpv cannot honour', () {
      expect(
        clientFor(
          Uri.parse('https://nas.local'),
          pin: fingerprint,
        ).playbackTransport(),
        PlaybackTransport.pinnedTls,
      );
    });

    test('a pin over plain http is still plainHttp', () {
      // There is no handshake to pin, so reporting pinnedTls would refuse
      // playback for a protection that was never in effect.
      expect(
        clientFor(
          Uri.parse('http://nas.local'),
          pin: fingerprint,
        ).playbackTransport(),
        PlaybackTransport.plainHttp,
      );
    });
  });
}
