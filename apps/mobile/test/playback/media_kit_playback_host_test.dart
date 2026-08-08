import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/media_kit_playback_host.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../support/fake_mpv_player.dart';

AudioTrack _audio(
  String id, {
  String? language,
  String? title,
  String? codec,
}) => AudioTrack(id, title, language, codec: codec);

Tracks _tracks(List<AudioTrack> audio) =>
    Tracks(video: const [], audio: audio, subtitle: const []);

PlaybackRequest _request({
  bool verifyTls = false,
  Duration startAt = Duration.zero,
  Map<String, String> headers = const {'Cookie': 'filefin_session=secret'},
}) => PlaybackRequest(
  url: Uri.parse('http://nas.local/api/media/abc/file/2'),
  headers: headers,
  startAt: startAt,
  verifyTls: verifyTls,
);

void main() {
  late FakeMpvPlayer player;
  late MediaKitPlaybackHost host;

  setUp(() {
    player = FakeMpvPlayer();
    host = MediaKitPlaybackHost(player);
    addTearDown(host.dispose);
  });

  group('open', () {
    test('carries the url, the headers and the start position', () async {
      await host.open(_request(startAt: const Duration(seconds: 42)));

      final media = player.opened.single;
      expect(media.uri, 'http://nas.local/api/media/abc/file/2');
      expect(media.httpHeaders, {'Cookie': 'filefin_session=secret'});
      // `start:` rather than open-then-seek, so playback begins at the resume
      // position instead of showing a second of the beginning first.
      expect(media.start, const Duration(seconds: 42));
    });

    test('sets tls-verify BEFORE opening, never after', () async {
      await host.open(_request(verifyTls: true));

      expect(player.calls.first, 'setProperty(tls-verify=yes)');
      expect(player.calls[1], startsWith('open('));
    });

    test('an unverifiable pinned server is opened with verification off', () {
      // D10: the user accepted a certificate the OS does not trust, so turning
      // verification on would refuse the very certificate they accepted. The
      // refusal lives in `decide()`; by the time it reaches here the choice
      // has been made.
      expect(
        host.open(_request()).then((_) => player.properties),
        completion(['tls-verify=no']),
      );
    });
  });

  group('transport controls', () {
    test('play, pause and seek delegate unchanged', () async {
      await host.play();
      await host.pause();
      await host.seek(const Duration(seconds: 7));

      expect(player.calls, ['play', 'pause', 'seek(7000ms)']);
    });

    test('volume is 0..1 here and 0..100 to libmpv', () async {
      await host.setVolume(0);
      await host.setVolume(0.5);
      await host.setVolume(1);

      expect(player.volumes, [0.0, 50.0, 100.0]);
    });

    test('a volume outside the range is clamped, not passed through', () async {
      // A slider that overshoots by a rounding error must not hand libmpv 110.
      await host.setVolume(-1);
      await host.setVolume(2);

      expect(player.volumes, [0.0, 100.0]);
    });
  });

  group('tracks', () {
    test("libmpv's synthetic auto and no entries are dropped", () async {
      // media_kit prepends mpv's own "pick for me" and "none" pseudo-entries
      // to every list. Showing them would offer two options that look like
      // languages and are not, and "1 audio track" would read as three.
      final seen = <PlaybackTracks>[];
      host.tracks.listen(seen.add);

      player.emitTracks(
        _tracks([_audio('auto'), _audio('no'), _audio('1', language: 'eng')]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.audio, [
        const PlaybackTrackRef(id: '1', label: 'eng'),
      ]);
    });

    for (final (name, track, expected) in <(String, AudioTrack, String)>[
      ('language wins', _audio('1', language: 'jpn', title: 'Stereo'), 'jpn'),
      (
        'title when there is no language',
        _audio('2', title: 'Commentary'),
        'Commentary',
      ),
      (
        'codec and id when there is neither',
        _audio('3', codec: 'aac'),
        'aac (3)',
      ),
      ('the id alone when libmpv knew nothing', _audio('4'), 'Track 4'),
    ]) {
      test('the label falls back: $name', () async {
        final seen = <PlaybackTracks>[];
        host.tracks.listen(seen.add);

        player.emitTracks(_tracks([track]));
        await Future<void>.delayed(Duration.zero);

        expect(seen.single.audio.single.label, expected);
      });
    }

    test('an empty string is treated as absent, not shown', () async {
      final seen = <PlaybackTracks>[];
      host.tracks.listen(seen.add);

      player.emitTracks(
        _tracks([_audio('5', language: '', title: '', codec: '')]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen.single.audio.single.label, 'Track 5');
    });

    test('selecting a track passes the id libmpv reported', () async {
      await host.selectAudioTrack(
        const PlaybackTrackRef(id: '2', label: 'jpn'),
      );

      expect(player.audio.single.id, '2');
      expect(player.audio.single.title, 'jpn');
      expect(player.audio.single.language, isNull);
    });
  });

  group('subtitles', () {
    test('a sidecar is sent as DATA, never as a uri', () async {
      // The whole reason `SubtitleSource` carries text rather than a URL: the
      // sidecar route is authenticated, so a `sub-add` would use libmpv's own
      // unverified HTTP with no cookie jar, no F3 retry and no pin.
      await host.selectSubtitleTrack(
        const SubtitleSource(
          index: SubtitleIndex(0),
          label: 'English',
          data: 'WEBVTT\n\n00:00.000 --> 00:02.000\nHello\n',
        ),
      );

      final track = player.subtitles.single;
      expect(track.id, contains('WEBVTT'));
      expect(track.uri, isFalse);
      expect(track.data, isTrue);
      expect(track.title, 'English');
    });

    test('null turns subtitles off', () async {
      await host.selectSubtitleTrack(null);

      expect(player.subtitles.single.id, 'no');
      expect(player.subtitles.single.data, isFalse);
    });
  });

  group('the streams pass straight through', () {
    test('position, duration, playing, completed and errors', () async {
      final positions = <Duration>[];
      final durations = <Duration>[];
      final playing = <bool>[];
      final completed = <bool>[];
      final errors = <String>[];
      host.position.listen(positions.add);
      host.duration.listen(durations.add);
      host.playing.listen(playing.add);
      host.completed.listen(completed.add);
      host.errors.listen(errors.add);

      player
        ..emitPosition(const Duration(seconds: 1))
        ..emitDuration(const Duration(seconds: 3))
        ..emitPlaying(value: false)
        ..emitCompleted()
        ..emitError('Failed to open http://nas.local/api/media/abc/file/2.');
      await Future<void>.delayed(Duration.zero);

      expect(positions, [const Duration(seconds: 1)]);
      expect(durations, [const Duration(seconds: 3)]);
      expect(playing, [false]);
      expect(completed, [true]);
      // A string, not a status code. libmpv does not surface one — a 401 and a
      // missing file produce the same sentence — which is why
      // `PlayerController` asks `me()` instead of parsing this.
      expect(errors.single, startsWith('Failed to open'));
    });
  });

  test('the surface comes from the player, so no test builds a Video', () {
    expect(host.buildSurface(), isNotNull);
    expect(player.calls, ['buildSurface']);
  });

  test('disposing the host disposes the engine', () async {
    await host.dispose();

    expect(player.disposed, isTrue);
  });
}
