@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/media_kit_playback_host.dart';
import 'package:filefin_mobile/src/playback/mpv_player.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../test/support/libmpv.dart';
import 'support/live.dart';

/// The milestone's real proof: **libmpv playing the real server's bytes**.
///
/// Everything in the chain is the shipped thing — the `filefin` binary, the
/// seeded H.264 file on disk, the socket, the session cookie minted by
/// `playbackHeaders()`, `MediaKitPlaybackHost`, `RealMpvPlayer`, and mpv's own
/// demuxer and decoder. What is *not* real is the video output:
/// `NativePlayer.test = true` forces `vo=null` and `ao=null`, so nothing
/// rasterises and nothing reaches a speaker. Pixels are
/// `docs/verification-backlog.md` row 15, on a device.
///
/// **The negative control is in its own file**, `playback_no_cookie_test.dart`,
/// and that is not tidiness. `Media`'s constructor reads
/// `httpHeaders ?? cache[uri]?.httpHeaders` from a **global static cache keyed
/// by URI**, so a second open of the same URL with no headers silently inherits
/// this one's cookie: measured at M4.0/E3, where the control "passed" in-process
/// and failed correctly only in a fresh one. `flutter test` runs each file in
/// its own `flutter_tester` process, which is what makes that file's cache
/// genuinely empty.
///
/// Every wait is bounded and the failure is a timeout with a name, because the
/// alternative — a bare `await` on a stream that never fires — is a hung gate.
void main() {
  late Duration duration;
  late PlaybackTracks tracks;
  late Duration firstPast1s;
  late Duration afterSeek;
  late bool completedFired;
  late List<String> subtitleCue;

  setUpAll(() async {
    HttpOverrides.global = null;
    ensureLibmpv();
    useHeadlessPlayer();

    final api = await liveApi();
    final categories = await api.categories();
    final films = categories.firstWhere((c) => c.leaf == 'Films');
    final film = (await api.categoryMedia(films.id)).single;
    final detail = await api.mediaDetail(film.id);
    final sidecar = detail.files.single.subtitles.single;

    // THE COOKIE IS FETCHED THE WAY THE PLAYER FETCHES IT. `playbackHeaders()`
    // makes an authenticated `me()` first, so F3 has renewed before the header
    // is handed to an engine that cannot see a status code.
    final headers = await api.playbackHeaders();
    final vtt = await api.subtitleText(
      film.id,
      const FileIndex(0),
      sidecar.index,
    );

    final raw = Player();
    final host = MediaKitPlaybackHost(RealMpvPlayer.over(raw));
    addTearDown(host.dispose);

    // Subscribed BEFORE the open, so nothing that arrives during load is
    // missed — mpv reports duration and tracks as part of loading the file.
    final durationSeen = raw.stream.duration.firstWhere(
      (d) => d > Duration.zero,
    );
    final tracksSeen = host.tracks.firstWhere((t) => t.audio.isNotEmpty);
    final past1s = host.position.firstWhere(
      (p) => p > const Duration(seconds: 1),
    );
    final cueSeen = raw.stream.subtitle.firstWhere(
      (lines) => lines.any((l) => l.contains('Hello fixture')),
    );
    final completed = host.completed.firstWhere((done) => done);

    await host.open(
      PlaybackRequest(
        url: api.fileUrl(film.id, const FileIndex(0)),
        headers: headers.headers,
        startAt: Duration.zero,
        // The seeded server is plain HTTP and has no TLS listener at all
        // (§8 R5), so `tls-verify` has nothing to verify here. D10's two other
        // arms are `docs/risks.md` R6's measurement and backlog row 19.
        verifyTls: false,
      ),
    );
    await host.selectSubtitleTrack(
      SubtitleSource(index: sidecar.index, label: 'English', data: vtt),
    );
    await host.play();

    duration = await durationSeen.timeout(const Duration(seconds: 20));
    tracks = await tracksSeen.timeout(const Duration(seconds: 20));
    subtitleCue = await cueSeen.timeout(const Duration(seconds: 20));
    firstPast1s = await past1s.timeout(const Duration(seconds: 30));

    final landed = host.position.firstWhere(
      (p) => p >= const Duration(milliseconds: 1900),
    );
    await host.seek(const Duration(seconds: 2));
    afterSeek = await landed.timeout(const Duration(seconds: 20));

    completedFired = await completed.timeout(const Duration(seconds: 30));
  });

  test('the real bytes decode: mpv reports the seeded file is 3 seconds', () {
    // The single assertion that says the cookie worked. Without it the server
    // answers 401, mpv reports a failure on its error stream and no duration
    // ever arrives — which is exactly what the negative-control file asserts.
    expect(duration.inMilliseconds, greaterThan(2500));
    expect(duration.inMilliseconds, lessThan(4000));
  });

  test('the engine finds the audio track, with no synthetic entries', () {
    // F7's audio menu has no other possible source: `fileInfo` carries
    // `subtitles[]` and no audio array at all (SPEC §3.3, C2).
    expect(tracks.audio, isNotEmpty);
    expect(
      tracks.audio.map((t) => t.id),
      isNot(contains('auto')),
      reason: "mpv's pseudo-entries are dropped by the adapter",
    );
    expect(tracks.audio.map((t) => t.id), isNot(contains('no')));
    expect(tracks.audio.single.label, isNotEmpty);
  });

  test('position advances past one second of real playback', () {
    expect(firstPast1s, greaterThan(const Duration(seconds: 1)));
    expect(firstPast1s, lessThanOrEqualTo(duration));
  });

  test('a seek lands where it was aimed', () {
    // NF3's functional half. The latency half is on a device, over a LAN
    // (`docs/verification-backlog.md` row 16) — a loopback socket cannot say
    // anything about 500 ms on a phone.
    expect(afterSeek, greaterThanOrEqualTo(const Duration(milliseconds: 1900)));
  });

  test('completed fires at the end of the file', () {
    // The trigger for the `ended` report, and the only one that carries
    // `position: duration` so the 0.90 crossing is unambiguous.
    expect(completedFired, isTrue);
  });

  test('a sidecar fetched through the API renders as a real cue', () {
    // E4, end to end: the server's own `text/vtt`, fetched with the cookie
    // through `LibraryApi`, handed to `SubtitleTrack.data`, rendered by mpv.
    // Nothing here went through libmpv's own unauthenticated HTTP, which is
    // why `SubtitleSource` carries text rather than a URL.
    expect(subtitleCue.join(' '), contains('Hello fixture'));
  });
}
