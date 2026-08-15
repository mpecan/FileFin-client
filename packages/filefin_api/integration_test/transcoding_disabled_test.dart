import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// The 415 against a **real** `filefin` with transcoding switched off.
///
/// The switch is `transcodeEnabled` in the server's own `.filefin.json`, which
/// `FixtureRun.create(transcoding: false)` writes into the private copy beside
/// the port and the data directory. The admin route that would do the same
/// thing is forbidden by C4, and this is better anyway: no restart, no shared
/// state, and the seeded `$RUN` is never touched — a `transcodeEnabled: false`
/// left there turns the 307 test below red on unmodified code.
void main() {
  Future<(FileFinTestServer, FileFinClient)> signedInTo({
    required bool transcoding,
  }) async {
    final server = await startServer(transcoding: transcoding);
    final client = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(client.close);
    await client.login(seededCredentials);
    return (server, client);
  }

  Future<MediaDetail> showDetail(FileFinClient client) async {
    final categories = await client.categories();
    final shows = categories.firstWhere((c) => c.leaf == 'Shows');
    final show = (await client.categoryMedia(shows.id)).single;
    return client.mediaDetail(show.id);
  }

  Future<MediaDetail> filmDetail(FileFinClient client) async {
    final categories = await client.categories();
    final films = categories.firstWhere((c) => c.leaf == 'Films');
    final film = (await client.categoryMedia(films.id)).single;
    return client.mediaDetail(film.id);
  }

  test('with transcoding OFF the pre-flight refuses the HEVC show', () async {
    final (_, client) = await signedInTo(transcoding: false);
    final detail = await showDetail(client);

    await expectLater(
      client.requirePlayable(detail.id, const FileIndex(0)),
      throwsA(
        isA<TranscodingDisabled>().having(
          (e) => e.requested,
          'requested',
          client.fileUrl(detail.id, const FileIndex(0)),
        ),
      ),
    );
  });

  test('`transcode` is STILL true on a server that will not do it', () async {
    // The load-bearing measurement of the whole design (M5.0/E-B), gated here
    // rather than left in a scratchpad. `fileNeedsTranscode` never consults
    // whether transcoding is enabled — it answers "this file is not
    // browser-native" — so the client's guard still fires and the pre-flight
    // still runs. If this ever flips false, `PlayerController` takes the
    // direct-play branch, the pre-flight never runs, and F12's message is
    // unreachable.
    final (_, client) = await signedInTo(transcoding: false);
    final detail = await showDetail(client);

    expect(detail.files.first.transcode, isTrue);
  });

  test('the NEGATIVE CONTROL: the H.264 film still plays', () async {
    // Without this the suite could pass against a server that refused
    // everything — a broken config, a missing data directory, a typo in the
    // key name — and would report that as F12 working.
    final (server, client) = await signedInTo(transcoding: false);
    final detail = await filmDetail(client);

    expect(detail.files.single.transcode, isFalse);
    await client.requirePlayable(detail.id, const FileIndex(0));

    final probe = HttpClient();
    addTearDown(() => probe.close(force: true));
    final request = await probe.getUrl(
      client.fileUrl(detail.id, const FileIndex(0)),
    );
    final sessionHeaders = await client.sessions.headers();
    request.headers.add(HttpHeaders.cookieHeader, sessionHeaders!['Cookie']!);
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, 200);
    expect(response.headers.value('accept-ranges'), 'bytes');
    // The `logTail` is what turns a failure here into a diagnosis.
    expect(server.baseUrl.scheme, 'http');
  });

  test('with transcoding ON the same pre-flight returns (the 307)', () async {
    // The other side of the boundary, and the one that proves the pre-flight
    // is not simply refusing everything. `followRedirects` is off, so what
    // comes back is the 307 itself — dio never fetches the playlist and never
    // fetches a segment.
    final (_, client) = await signedInTo(transcoding: true);
    final detail = await showDetail(client);

    await client.requirePlayable(detail.id, const FileIndex(0));
  });

  test('a file index the item does not have is NotFound, not a 415', () async {
    final (_, client) = await signedInTo(transcoding: false);
    final detail = await showDetail(client);

    await expectLater(
      client.requirePlayable(detail.id, const FileIndex(99)),
      throwsA(isA<NotFound>()),
    );
  });
}
