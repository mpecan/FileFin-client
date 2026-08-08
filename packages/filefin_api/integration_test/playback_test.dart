@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// The playback endpoints against the real binary, and one differential check.
///
/// **The differential check is what this suite is for.** `applyProgress` and
/// `deriveView` are a Dart transcription of `internal/state/engine.go`, and the
/// 601 captured vectors prove the transcription against that package run
/// directly. They do not prove that the HTTP route in front of it stores what
/// the engine returns. So every report below is posted to the live server, the
/// detail is re-read, and the server's own `continueIndex`/`continueSeconds`
/// are compared against what the pure functions predicted for the same input.
/// A drift anywhere in that path — a rounding difference, a field name, a
/// handler that clamps — fails here rather than at a user's resume position.
void main() {
  late FileFinClient client;
  late MediaId film;
  late MediaId show;

  setUp(() async {
    final server = await startServer();
    client = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(client.close);
    await client.login(seededCredentials);
    final categories = await client.categories();
    film = (await client.categoryMedia(
      categories.firstWhere((c) => c.leaf == 'Films').id,
    )).single.id;
    show = (await client.categoryMedia(
      categories.firstWhere((c) => c.leaf == 'Shows').id,
    )).single.id;
  });

  /// Posts [report], then asserts the server agrees with the pure engine.
  ///
  /// The prediction is made from the state the server *had*, so the two sides
  /// see the same input and any disagreement is the round trip's.
  Future<WatchView> postAndCompare(MediaId id, ProgressReport report) async {
    final before = await client.mediaDetail(id);
    final fileCount = before.files.length;
    final predicted = deriveView(
      applyProgress(
        WatchState.fromDetail(before),
        report,
        fileCount: fileCount,
      ),
      fileCount: fileCount,
    );

    await client.postProgress(id, report);

    final after = await client.mediaDetail(id);
    final observed = deriveView(
      WatchState.fromDetail(after),
      fileCount: fileCount,
    );

    expect(
      after.continueIndex,
      predicted.continueIndex.value,
      reason: 'continueIndex: the server and applyProgress disagree',
    );
    expect(
      after.continueSeconds,
      predicted.continueSeconds,
      reason: 'continueSeconds: the server and applyProgress disagree',
    );
    expect(
      after.watched,
      predicted.watched,
      reason: 'watched: the server and applyProgress disagree',
    );
    expect(observed, predicted, reason: 'deriveView over the real payload');
    return observed;
  }

  test('a report is accepted and stored where the engine says', () async {
    // 1.0s of 3.0s is 33%, well below the 0.90 threshold: the pointer moves to
    // the reported second and nothing crosses.
    final view = await postAndCompare(
      show,
      const ProgressReport(
        file: FileIndex(0),
        position: 1.4,
        duration: 3,
      ),
    );

    // `round` is Go's `int(x + 0.5)`, not banker's rounding and not truncation:
    // 1.4 stores as 1. Asserting the literal is what makes a change to
    // `roundReportedSeconds` fail here as well as in the unit suite.
    expect(view.continueSeconds, 1);
    expect(view.continueIndex, const FileIndex(0));
    expect(view.watched, isFalse);
  });

  test('every event value is accepted — the engine ignores it', () async {
    // `state.Apply` never reads `event`, so `seek` — the one value that is ours
    // rather than upstream's — must not be rejected. Nothing but a live server
    // can say that.
    for (final event in ProgressEvent.values) {
      await client.postProgress(
        show,
        ProgressReport(
          file: const FileIndex(0),
          position: 2,
          duration: 3,
          event: event,
        ),
      );
    }

    final detail = await client.mediaDetail(show);
    expect(detail.continueSeconds, 2);
    expect(detail.continueIndex, 0);
  });

  test(
    'crossing a NON-last file advances the pointer and stays unwatched',
    () async {
      // Arm one of the asymmetry: 2.9 of 3.0 is 96.7%, over the threshold, on
      // file 0 of two. The pointer aims at the NEXT file at zero seconds and
      // `watched` does not move.
      final view = await postAndCompare(
        show,
        const ProgressReport(
          file: FileIndex(0),
          position: 2.9,
          duration: 3,
        ),
      );

      expect(view.continueIndex, const FileIndex(1));
      expect(view.continueSeconds, 0);
      expect(view.watched, isFalse);
      expect(
        view.perFile,
        [true, false],
        reason: 'the file AT the pointer is not watched — you are inside it',
      );
    },
  );

  test('crossing the LAST file sets watched and leaves the pointer', () async {
    // Arm two, and the reason this is a separate test rather than a second
    // expectation: the two arms are the same input on different indices, and a
    // handler that advanced unconditionally would pass arm one.
    await client.postProgress(
      show,
      const ProgressReport(file: FileIndex(1), position: 1, duration: 3),
    );

    final view = await postAndCompare(
      show,
      const ProgressReport(
        file: FileIndex(1),
        position: 2.9,
        duration: 3,
      ),
    );

    expect(view.watched, isTrue);
    expect(
      view.continueIndex,
      const FileIndex(1),
      reason: 'the pointer stays on the last file rather than running off it',
    );
    expect(view.perFile, [true, true], reason: 'the folder flag wins');
  });

  test('the pointer never moves backwards, on the real server too', () async {
    await client.postProgress(
      show,
      const ProgressReport(file: FileIndex(1), position: 2, duration: 3),
    );

    final view = await postAndCompare(
      show,
      const ProgressReport(file: FileIndex(0), position: 1, duration: 3),
    );

    expect(view.continueIndex, const FileIndex(1));
    expect(view.continueSeconds, 2);
  });

  test(
    'a file index outside the list is BadRequest, not a retryable 500',
    () async {
      // `media.go:511`. It matters that this is its own variant: a progress
      // reporter that treated it as retryable would post the same rejected body
      // on every position tick for the rest of the file.
      await expectLater(
        client.postProgress(
          film,
          const ProgressReport(file: FileIndex(99), position: 1, duration: 3),
        ),
        throwsA(
          isA<BadRequest>().having(
            (e) => e.body,
            'body',
            contains('bad file index'),
          ),
        ),
      );
    },
  );

  test('the sidecar comes back as WebVTT, converted from SRT', () async {
    // The seed writes an `.srt`; the server converts. `SubtitleTrack.data`
    // needs WEBVTT, so the first token is the contract.
    final text = await client.subtitleText(
      film,
      const FileIndex(0),
      const SubtitleIndex(0),
    );

    expect(text, startsWith('WEBVTT'));
    expect(text, contains('Hello fixture'));
    expect(
      text,
      contains('-->'),
      reason: 'a cue timing, so this is a subtitle file and not a stub',
    );
  });

  test('a sidecar index the file does not have is a 404', () async {
    await expectLater(
      client.subtitleText(film, const FileIndex(0), const SubtitleIndex(9)),
      throwsA(isA<NotFound>()),
    );
  });

  test('the direct-play file answers a byte range with 206', () async {
    // NF3's whole basis: seeking on the direct path is a byte range, and only
    // the real `http.ServeContent` can say whether this server does them. The
    // request goes through a bare HttpClient because `FileFinClient` does not
    // fetch media bytes at all — libmpv does — so this is the same shape the
    // engine will use, cookie included.
    final headers = await client.playbackHeaders();
    final url = client.fileUrl(film, const FileIndex(0));
    final http = HttpClient();
    addTearDown(() => http.close(force: true));

    final request = await http.getUrl(url);
    headers.headers.forEach(request.headers.add);
    request.headers.add(HttpHeaders.rangeHeader, 'bytes=0-49');
    final response = await request.close();
    final bytes = await response.fold<int>(0, (n, chunk) => n + chunk.length);

    expect(response.statusCode, 206);
    expect(response.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(
      response.headers.value(HttpHeaders.contentRangeHeader),
      startsWith('bytes 0-49/'),
    );
    expect(bytes, 50);
  });

  test('the transcoding file 307s rather than serving bytes', () async {
    // The other half of SPEC §3.4, and the reason the seeded library holds two
    // items. It is a 307 here because the seeded cache rows are UNPROBED, so
    // `fileNeedsTranscode` falls back to the extension — see
    // `tool/spikes/e5_mkv_direct_play.sh` for the probed arm.
    final headers = await client.playbackHeaders();
    final http = HttpClient()..autoUncompress = false;
    addTearDown(() => http.close(force: true));

    final request = await http.getUrl(client.fileUrl(show, const FileIndex(0)));
    headers.headers.forEach(request.headers.add);
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>();

    expect(response.statusCode, 307);
    expect(
      response.headers.value(HttpHeaders.locationHeader),
      endsWith('/hls/index.m3u8'),
    );
  });

  test('playbackHeaders carries a real cookie and redacts it', () async {
    final headers = await client.playbackHeaders();

    expect(headers.headers.keys, ['Cookie']);
    expect(headers.headers['Cookie'], startsWith('$sessionCookieName='));
    expect(
      headers.headers['Cookie'],
      isNot(endsWith('=')),
      reason:
          'an empty cookie would be a 401 inside mpv and look like a '
          'missing file',
    );
    expect('$headers', 'PlaybackSessionHeaders(Cookie: <redacted>)');
  });

  test('playbackTransport reads plain HTTP for this server', () async {
    // The binary has no TLS listener at all (§8 R5), so this is the only
    // transport a live suite can observe. D10's other two arms are unit-tested
    // against a Dart `bindSecure` in `playback_endpoints_test.dart`.
    expect(client.playbackTransport(), PlaybackTransport.plainHttp);
  });
}
