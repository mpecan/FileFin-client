@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';
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
  /// A controller over [detail], with a fresh fake engine behind it.
  (PlayerController, FakePlaybackHost) playerFor(
    LibraryApi api,
    MediaDetail detail,
  ) {
    final engine = FakePlaybackHost();
    final controller = PlayerController(
      api: api,
      host: engine,
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
    return (controller, engine);
  }

  /// The one item in [leaf], fully loaded.
  Future<MediaDetail> only(LibraryApi api, String leaf) async {
    final categories = await api.categories();
    final category = categories.firstWhere((c) => c.leaf == leaf);
    final item = (await api.categoryMedia(category.id)).single;
    return api.mediaDetail(item.id);
  }

  test('a real 415 becomes F12s sentence, and open is never called', () async {
    HttpOverrides.global = null;
    final api = await liveApi(transcoding: false);
    final detail = await only(api, 'Shows');

    // E-B, gated against the real binary: the flag the client's guard reads is
    // still true on a server that will not honour it.
    expect(detail.files.first.transcode, isTrue);

    final (controller, engine) = playerFor(api, detail);

    await controller.start();

    expect(
      controller.failure,
      'This file needs transcoding and the server has it turned off.',
    );
    expect(controller.unplayable, isNotNull);
    expect(engine.opened, isEmpty);
    // `anyElement(startsWith(...))`: `open` is recorded as `'open($request)'`,
    // so `isNot(contains('open'))` compared an element to a string no element
    // can equal and could never fail. See `player_transcoding_test.dart`.
    expect(engine.calls, isNot(anyElement(startsWith('open('))));
  });

  test('the SERVER control: the film opens on the same server', () async {
    // Without it, a server that refused everything — a broken copy, a missing
    // data directory, a mistyped config key — would look exactly like F12
    // working.
    HttpOverrides.global = null;
    final api = await liveApi(transcoding: false);
    final (controller, engine) = playerFor(api, await only(api, 'Films'));

    await controller.start();

    expect(controller.failure, isNull);
    expect(controller.unplayable, isNull);
    expect(engine.opened, hasLength(1));
  });

  test('the PRE-FLIGHT control: the same show opens when it is on', () async {
    // **The control the film could not be.** The film is `transcode: false`,
    // so `_open`'s guard skips the pre-flight entirely and the test above
    // never executes the code it is controlling for: mutating
    // `requirePlayable` to throw unconditionally left BOTH tests above green.
    // This one is the same show, the same route and the same guard, with only
    // the server's `transcodeEnabled` different — so it runs the pre-flight,
    // and it is red the moment the pre-flight refuses something it should not.
    HttpOverrides.global = null;
    final api = await liveApi();
    final detail = await only(api, 'Shows');
    expect(detail.files.first.transcode, isTrue);
    final (controller, engine) = playerFor(api, detail);

    await controller.start();

    expect(controller.failure, isNull);
    expect(controller.unplayable, isNull);
    expect(engine.opened, hasLength(1));
  });
}
