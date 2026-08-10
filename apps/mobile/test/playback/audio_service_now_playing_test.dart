import 'package:audio_service/audio_service.dart';
import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:filefin_mobile/src/playback/audio_service_now_playing.dart';
import 'package:filefin_mobile/src/playback/now_playing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_audio_service_platform.dart';

/// F14's adapter, against `audio_service`'s own platform seam.
///
/// **`AudioService.init` is a one-shot global** — it asserts on a second call —
/// so exactly one test here invokes [openNowPlaying], and everything else
/// drives a [FileFinAudioHandler] built directly. That is not a workaround: the
/// handler is where the OS's buttons arrive and the `mediaItem` /
/// `playbackState` subjects are where our metadata lands, so building one is
/// closer to the boundary than initialising a service would be.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileFinAudioHandler handler;
  late AudioServiceNowPlaying session;

  setUp(() {
    handler = FileFinAudioHandler();
    session = AudioServiceNowPlaying(handler);
  });

  group('what crosses the boundary', () {
    test('a multi-file item publishes its file as the artist line', () async {
      await session.publish(
        const NowPlayingItem(
          title: 'Direct Play Movie',
          subtitle: 'S1E2',
          duration: Duration(seconds: 100),
        ),
      );

      final item = handler.mediaItem.value!;
      // The id is a constant rather than the `MediaId`, and it is asserted so
      // that stays a decision: a library identifier in an OS notification is
      // one more place it can leak.
      expect(item.id, 'filefin');
      expect(item.title, 'Direct Play Movie');
      expect(item.artist, 'S1E2');
      expect(item.duration, const Duration(seconds: 100));
    });

    test('an empty file label is absent rather than blank', () async {
      await session.publish(
        const NowPlayingItem(
          title: 'Film',
          subtitle: '',
          duration: Duration(seconds: 3),
        ),
      );

      expect(handler.mediaItem.value!.artist, isNull);
    });

    test('a zero duration is UNKNOWN, not a zero-length scrubber', () async {
      await session.publish(
        const NowPlayingItem(
          title: 'Film',
          subtitle: '',
          duration: Duration.zero,
        ),
      );

      expect(handler.mediaItem.value!.duration, isNull);
    });

    test('playing offers Pause and paused offers Play', () async {
      await session.update(
        const NowPlayingTransport(
          playing: true,
          position: Duration(seconds: 7),
          duration: Duration(seconds: 100),
        ),
      );

      var state = handler.playbackState.value;
      expect(state.playing, isTrue);
      expect(state.updatePosition, const Duration(seconds: 7));
      expect(state.controls.single.action, MediaAction.pause);
      expect(state.systemActions, contains(MediaAction.seek));
      expect(state.processingState, AudioProcessingState.ready);

      await session.update(
        const NowPlayingTransport(
          playing: false,
          position: Duration(seconds: 7),
          duration: Duration(seconds: 100),
        ),
      );

      state = handler.playbackState.value;
      expect(state.playing, isFalse);
      expect(state.controls.single.action, MediaAction.play);
    });

    test(
      'clearing idles the transport, which is what stops the service',
      () async {
        await session.update(
          const NowPlayingTransport(
            playing: true,
            position: Duration(seconds: 7),
            duration: Duration(seconds: 100),
          ),
        );

        await session.clear();

        expect(
          handler.playbackState.value.processingState,
          AudioProcessingState.idle,
        );
        expect(handler.playbackState.value.playing, isFalse);
        expect(handler.playbackState.value.controls, isEmpty);
      },
    );
  });

  group('what comes back across it', () {
    test('the OS transport maps onto our three commands', () async {
      final seen = <TransportCommand>[];
      final sub = session.commands.listen(seen.add);
      addTearDown(sub.cancel);

      await handler.play();
      await handler.pause();
      await handler.seek(const Duration(seconds: 42));
      // The OS's own Stop, which this app has no separate answer for.
      await handler.stop();
      await pumpEventQueue();

      expect(seen, [
        const ResumeCommand(),
        const PauseCommand(),
        isA<SeekCommand>().having(
          (c) => c.to,
          'to',
          const Duration(seconds: 42),
        ),
        const PauseCommand(),
      ]);
    });
  });

  group('the artwork cache F14 declines to have', () {
    // Eleven methods, eleven throws. `AudioService.init` builds a
    // `DefaultCacheManager()` — a sqflite database and an HttpClient — unless
    // it is handed one, and F14 publishes no artwork at all.
    const cache = NoArtworkCache();

    test('every method refuses, and says why', () {
      expect(() => cache.getSingleFile('u'), throwsUnsupportedError);
      expect(() => cache.getFile('u'), throwsUnsupportedError);
      expect(() => cache.getFileStream('u'), throwsUnsupportedError);
      expect(() => cache.downloadFile('u'), throwsUnsupportedError);
      expect(() => cache.getFileFromCache('k'), throwsUnsupportedError);
      expect(() => cache.getFileFromMemory('k'), throwsUnsupportedError);
      expect(() => cache.putFile('u', Object()), throwsUnsupportedError);
      expect(
        () => cache.putFileStream('u', const Stream<List<int>>.empty()),
        throwsUnsupportedError,
      );
      expect(() => cache.removeFile('k'), throwsUnsupportedError);
      expect(cache.emptyCache, throwsUnsupportedError);
      expect(cache.dispose, throwsUnsupportedError);
    });
  });

  group('opening the session', () {
    test('configures the platform and routes its callbacks', () async {
      final platform = FakeAudioServicePlatform();
      AudioServicePlatform.instance = platform;

      final host = await openNowPlaying();

      expect(platform.calls, contains('setHandlerCallbacks'));
      expect(
        platform.calls,
        contains('configure(dev.filefin.playback|Playback)'),
      );

      final seen = <TransportCommand>[];
      final sub = host.commands.listen(seen.add);
      addTearDown(sub.cancel);

      // The OS side of the boundary, using the callbacks the platform was
      // handed rather than our own handler: this is the path a lock-screen
      // button really takes.
      await platform.callbacks!.pause(const PauseRequest());
      await pumpEventQueue();

      expect(seen, [const PauseCommand()]);

      await host.publish(
        const NowPlayingItem(
          title: 'Film',
          subtitle: '',
          duration: Duration(seconds: 3),
        ),
      );
      await pumpEventQueue();

      expect(platform.calls, contains('setMediaItem(Film)'));

      // The whole point of `clear()` publishing `idle` rather than reaching
      // for a stop method: audio_service turns that transition into the call
      // that takes the foreground notification down.
      await host.update(
        const NowPlayingTransport(
          playing: true,
          position: Duration.zero,
          duration: Duration(seconds: 3),
        ),
      );
      await pumpEventQueue();
      await host.clear();
      await pumpEventQueue();

      expect(platform.calls, contains('stopService'));

      // Memoised: a second player screen must reuse the one session rather
      // than trip `AudioService.init`'s assert.
      expect(await openNowPlaying(), same(host));
    });
  });
}
