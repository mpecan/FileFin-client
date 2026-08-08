import 'dart:async';

import 'package:filefin_mobile/src/playback/media_kit_playback_host.dart';
import 'package:filefin_mobile/src/playback/mpv_player.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../support/libmpv.dart';

/// `RealMpvPlayer` against a **real libmpv**, headlessly.
///
/// This suite exists because M4.0/E2 came back positive: `media_kit`'s core is
/// pure Dart over `dart:ffi`, only `media_kit_video` is a plugin, and a
/// `Player` genuinely constructs under `flutter test` — measured against
/// Homebrew's mpv 0.41.0, with a duration, a position past one second, an audio
/// track list and a `completed` event all arriving. Without that answer this
/// file would be the first uncovered code in the tree.
///
/// **No media file is opened here**, and that is deliberate rather than timid.
/// CI has no seeded library and no ffmpeg, so a suite that needed one would
/// either fail there or learn to skip. What this proves is that every
/// delegation in `RealMpvPlayer` reaches a real mpv context and that mpv
/// answers; real bytes, real decode and a real cookie are `test_live/`'s job
/// (`just it`), against the real server.
void main() {
  setUpAll(ensureLibmpv);

  late Player raw;
  late RealMpvPlayer player;

  setUp(() {
    // `vo=null` AND `ao=null` — without it mpv opens an audio device on a CI
    // box that has none (`real.dart:2507`).
    NativePlayer.test = true;
    raw = Player();
    player = RealMpvPlayer.over(raw);
  });

  tearDown(() async => player.dispose());

  test('every stream is wired to the engine, and none is null', () {
    expect(player.position, isA<Stream<Duration>>());
    expect(player.duration, isA<Stream<Duration>>());
    expect(player.playing, isA<Stream<bool>>());
    expect(player.completed, isA<Stream<bool>>());
    expect(player.tracks, isA<Stream<Tracks>>());
    expect(player.errors, isA<Stream<String>>());
  });

  test('setProperty reaches mpv, and mpv keeps the value', () async {
    // The single most consequential property this app sets. D10 rests on it
    // doing something, and M4.0/E6 proved it does in both directions: with
    // `tls-verify=yes` a self-signed peer was refused and the server logged
    // nothing; with `no` the same open played.
    await player.setProperty('tls-verify', 'yes');
    expect(
      await (raw.platform! as NativePlayer).getProperty('tls-verify'),
      'yes',
    );

    await player.setProperty('tls-verify', 'no');
    expect(
      await (raw.platform! as NativePlayer).getProperty('tls-verify'),
      'no',
    );
  });

  test('volume, play, pause and seek are accepted by a real context', () async {
    await player.setVolume(50);
    await player.play();
    await player.pause();
    await player.seek(Duration.zero);

    expect(raw.state.volume, 50);
  });

  test('the track setters reach mpv without a file open', () async {
    // Not a real selection — nothing is loaded — but it proves the two
    // delegations reach a real context and that mpv accepts the shapes the
    // adapter builds, including the `SubtitleTrack.data` route the sidecars
    // use.
    await player.setAudioTrack(const AudioTrack('auto', null, null));
    await player.setSubtitleTrack(SubtitleTrack.no());
    await player.setSubtitleTrack(
      SubtitleTrack.data('WEBVTT\n\n', title: 'English'),
    );

    expect(raw.state.track.subtitle.data, isTrue);
  });

  test('the default constructor loads libmpv before building the player', () {
    // The ordering is what this pins: a field initialiser runs before the
    // constructor body, so `_player = Player()` with `ensureInitialized()` in
    // the body would construct against an unloaded library. The suite has
    // already resolved a path, so passing it here is what production does with
    // a null on a device.
    final built = RealMpvPlayer(libmpv: resolvedLibmpv);
    addTearDown(built.dispose);

    expect(built.position, isA<Stream<Duration>>());
  });

  test(
    'opening something that does not exist surfaces an error',
    () async {
      // libmpv reports failure on its error stream and NOT as a thrown
      // exception, which is the whole reason `PlaybackHost.errors` is a
      // stream of strings rather than a Future that rejects.
      final errors = <String>[];
      final sub = player.errors.listen(errors.add);
      addTearDown(sub.cancel);

      await player.open(Media('/nonexistent/filefin/no-such-file.mkv'));
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(errors, isNotEmpty);
      expect(errors.first, contains('no-such-file.mkv'));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'the host drives the real engine, not just the fake',
    () async {
      // The translation layer is tested exhaustively against `FakeMpvPlayer`;
      // this is the one case proving the two agree about what mpv accepts. A
      // `tls-verify` value mpv rejected, or a `Media` it could not build,
      // would pass every fake-backed test in the suite.
      final host = MediaKitPlaybackHost(player);

      await host.open(
        PlaybackRequest(
          url: Uri.parse('file:///nonexistent/filefin/no-such-file.mkv'),
          headers: const {'Cookie': 'filefin_session=irrelevant'},
          startAt: const Duration(seconds: 3),
          verifyTls: true,
        ),
      );

      expect(
        await (raw.platform! as NativePlayer).getProperty('tls-verify'),
        'yes',
      );
      // Awaited on the stream rather than read off `state`: mpv applies a
      // property change asynchronously and `open` had just reset the volume to
      // 100, so a synchronous read raced it.
      final volume = raw.stream.volume.firstWhere((v) => v == 25);
      await host.setVolume(0.25);
      expect(await volume, 25);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
