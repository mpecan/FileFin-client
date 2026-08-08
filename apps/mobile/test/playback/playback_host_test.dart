import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_playback_host.dart';

void main() {
  group('PlaybackRequest never prints a credential (§9, NF4)', () {
    final request = PlaybackRequest(
      url: Uri.parse('http://nas.local/api/media/abc/file/0'),
      headers: const {'Cookie': 'filefin_session=hunter2', 'X-Trace': 'on'},
      startAt: const Duration(seconds: 42),
      verifyTls: true,
    );

    test('the header NAMES print and the values do not', () {
      // The names are worth printing — "did it carry a Cookie at all?" is the
      // first question anyone debugging playback asks — and the values never
      // are. This is the one type that travels from `filefin_api` into a
      // widget, so it is the one most likely to end up in a log line.
      expect(request.toString(), contains('Cookie'));
      expect(request.toString(), contains('X-Trace'));
      expect(request.toString(), isNot(contains('hunter2')));
      expect(request.toString(), contains('<redacted>'));
    });

    test('the url, start and verify flag are visible', () {
      expect(request.toString(), contains('/api/media/abc/file/0'));
      expect(request.toString(), contains('42s'));
      expect(request.toString(), contains('verifyTls: true'));
    });
  });

  group("the port's value types", () {
    test('a track ref compares and prints by value', () {
      const a = PlaybackTrackRef(id: '1', label: 'English');
      const b = PlaybackTrackRef(id: '1', label: 'English');
      const c = PlaybackTrackRef(id: '2', label: 'English');
      const d = PlaybackTrackRef(id: '1', label: 'Japanese');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(a.toString(), 'PlaybackTrackRef(1, English)');
    });

    test('empty tracks are what a host reports before a file opens', () {
      expect(PlaybackTracks.empty.audio, isEmpty);
      expect(PlaybackTracks.empty.toString(), 'PlaybackTracks(0 audio)');
      expect(
        const PlaybackTracks(
          audio: [PlaybackTrackRef(id: '1', label: 'English')],
        ).toString(),
        'PlaybackTracks(1 audio)',
      );
    });

    test('a subtitle source prints its size, not its text', () {
      const source = SubtitleSource(
        index: SubtitleIndex(2),
        label: 'English',
        data: 'WEBVTT\n\n',
      );
      expect(source.toString(), 'SubtitleSource(2, English, 8 chars)');
    });
  });

  group('the fake host records what it was handed', () {
    test('every call and every payload', () async {
      final host = FakePlaybackHost();
      addTearDown(host.dispose);

      await host.open(
        PlaybackRequest(
          url: Uri.parse('http://nas.local/f'),
          headers: const {},
          startAt: const Duration(seconds: 5),
          verifyTls: false,
        ),
      );
      await host.play();
      await host.seek(const Duration(seconds: 42));
      await host.pause();
      await host.setVolume(0.5);
      await host.selectAudioTrack(
        const PlaybackTrackRef(id: '2', label: 'Japanese'),
      );
      await host.selectSubtitleTrack(null);
      host.buildSurface();

      expect(host.opened.single.startAt, const Duration(seconds: 5));
      expect(host.seeks, [const Duration(seconds: 42)]);
      expect(host.subtitles, [null]);
      expect(host.calls, [
        anything,
        'play',
        'seek(42000ms)',
        'pause',
        'setVolume(0.5)',
        'selectAudioTrack(2)',
        'selectSubtitleTrack(null)',
        'buildSurface',
      ]);
    });

    test('its streams carry what is pushed into them', () async {
      final host = FakePlaybackHost();
      final positions = <Duration>[];
      final durations = <Duration>[];
      final playing = <bool>[];
      final completed = <bool>[];
      final tracks = <PlaybackTracks>[];
      final errors = <String>[];
      host.position.listen(positions.add);
      host.duration.listen(durations.add);
      host.playing.listen(playing.add);
      host.completed.listen(completed.add);
      host.tracks.listen(tracks.add);
      host.errors.listen(errors.add);

      host
        ..emitPosition(const Duration(seconds: 1))
        ..emitDuration(const Duration(seconds: 3))
        ..emitPlaying(value: false)
        ..emitCompleted()
        ..emitTracks(PlaybackTracks.empty)
        ..emitError('Failed to open');
      await Future<void>.delayed(Duration.zero);

      expect(positions, [const Duration(seconds: 1)]);
      expect(durations, [const Duration(seconds: 3)]);
      expect(playing, [false]);
      expect(completed, [true]);
      expect(tracks, hasLength(1));
      expect(errors, ['Failed to open']);

      await host.dispose();
      expect(host.disposed, isTrue);
    });

    test('an open failure is raised, not swallowed', () async {
      final host = FakePlaybackHost()..openFailure = StateError('boom');
      addTearDown(host.dispose);
      await expectLater(
        host.open(
          PlaybackRequest(
            url: Uri.parse('http://nas.local/f'),
            headers: const {},
            startAt: Duration.zero,
            verifyTls: false,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
