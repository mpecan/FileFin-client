@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fake_playback_host.dart';
import '../test/support/fakes.dart';
import 'support/live.dart';

/// F12 end to end: a **real** transcoding-disabled server, a real client, a
/// real `PlayerController` — and a **fake** engine, deliberately.
///
/// The whole claim is that the engine is never opened, so putting a real one
/// behind it would prove nothing extra and would cost this file the thing that
/// makes it safe to run beside `hls_live_test.dart`: no mpv context, no SIGBUS
/// on teardown, no global URI-keyed header cache.
///
/// Its own file for the same reason `playback_no_cookie_test.dart` is: two live
/// suites in one process share more than a process.
void main() {
  test('a real 415 becomes F12s sentence, and open is never called', () async {
    HttpOverrides.global = null;
    final api = await liveApi(transcoding: false);
    final categories = await api.categories();
    final shows = categories.firstWhere((c) => c.leaf == 'Shows');
    final show = (await api.categoryMedia(shows.id)).single;
    final detail = await api.mediaDetail(show.id);

    // E-B, gated against the real binary: the flag the client's guard reads is
    // still true on a server that will not honour it.
    expect(detail.files.first.transcode, isTrue);

    final host = FakePlaybackHost();
    final controller = PlayerController(
      api: api,
      host: host,
      network: FakeNetworkStatus(),
      detail: detail,
      server: SavedServer(
        id: const ServerId('live'),
        name: 'Home NAS',
        baseUrl: Uri.parse('http://127.0.0.1'),
      ),
      prefs: const PlaybackPrefs(),
      initialFile: const FileIndex(0),
      startAt: Duration.zero,
    );
    addTearDown(controller.dispose);

    await controller.start();

    expect(
      controller.failure,
      'This file needs transcoding and the server has it turned off.',
    );
    expect(controller.unplayable, isNotNull);
    expect(host.opened, isEmpty);
    expect(host.calls, isNot(contains('open')));
  });

  test('the NEGATIVE CONTROL: the film opens on the same server', () async {
    // Without it, a server that refused everything — a broken copy, a missing
    // data directory, a mistyped config key — would look exactly like F12
    // working.
    HttpOverrides.global = null;
    final api = await liveApi(transcoding: false);
    final categories = await api.categories();
    final films = categories.firstWhere((c) => c.leaf == 'Films');
    final film = (await api.categoryMedia(films.id)).single;
    final detail = await api.mediaDetail(film.id);

    final host = FakePlaybackHost();
    final controller = PlayerController(
      api: api,
      host: host,
      network: FakeNetworkStatus(),
      detail: detail,
      server: SavedServer(
        id: const ServerId('live'),
        name: 'Home NAS',
        baseUrl: Uri.parse('http://127.0.0.1'),
      ),
      prefs: const PlaybackPrefs(),
      initialFile: const FileIndex(0),
      startAt: Duration.zero,
    );
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.failure, isNull);
    expect(controller.unplayable, isNull);
    expect(host.opened, hasLength(1));
  });
}
