import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/now_playing.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_now_playing.dart';
import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

/// F14's client half: what the lock screen is told, and what its buttons do.
///
/// Everything up to `NowPlayingHost` is here. What the OS then DREW is
/// `docs/verification-backlog.md` row N, and E-6's Android measurement in
/// `docs/risks.md` is the closest anything gets to it without a device.
const _id = MediaId('e4285edb34d5');

MediaDetail _detail({int files = 1}) => MediaDetail(
  id: _id,
  title: 'Direct Play Movie',
  files: [
    for (var i = 0; i < files; i++)
      FileInfo(
        index: FileIndex(i),
        name: 'ep$i',
        size: 10,
        season: files == 1 ? 0 : 1,
        episode: files == 1 ? 0 : i + 1,
      ),
  ],
);

final class _Network extends NetworkStatus {
  @override
  Future<NetworkType> current() async => NetworkType.wifi;
}

void main() {
  late FakeLibraryApi api;
  late FakePlaybackHost host;
  late FakeNowPlaying session;

  setUp(() {
    api = FakeLibraryApi()
      ..playbackHeadersResult = const PlaybackSessionHeaders({
        'Cookie': 'filefin_session=sess-1',
      })
      ..meResult = const AuthResult(user: 'sam');
    host = FakePlaybackHost();
    session = FakeNowPlaying();
    addTearDown(session.dispose);
  });

  PlayerController controllerFor({MediaDetail? detail, int initialFile = 0}) {
    final controller = PlayerController(
      api: api,
      host: host,
      network: _Network(),
      detail: detail ?? _detail(),
      server: SavedServer(
        id: const ServerId('home'),
        name: 'Home',
        baseUrl: Uri.parse('http://nas.local'),
      ),
      prefs: const PlaybackPrefs(),
      initialFile: FileIndex(initialFile),
      startAt: Duration.zero,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  NowPlayingBinder bind(PlayerController controller) {
    final binder = NowPlayingBinder(session: session, controller: controller);
    addTearDown(binder.dispose);
    return binder;
  }

  group('what the lock screen is told', () {
    test('binding publishes the item at once, before anything plays', () {
      bind(controllerFor());

      expect(session.published, hasLength(1));
      expect(session.published.single.title, 'Direct Play Movie');
    });

    test('a single-file item carries no file label under its own title', () {
      bind(controllerFor());

      expect(session.published.single.subtitle, '');
    });

    test('a multi-file item names WHICH file, so Next is visible', () async {
      final controller = controllerFor(detail: _detail(files: 2));
      bind(controller);
      await controller.start();

      expect(session.published.single.subtitle, 'S1E1');

      await controller.next();

      expect(session.published, hasLength(2));
      expect(session.published.last.subtitle, 'S1E2');
    });

    test('the transport follows the engine', () async {
      final controller = controllerFor();
      bind(controller);
      await controller.start();
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitPlaying(value: true)
        ..emitPosition(const Duration(seconds: 25));
      await pumpEventQueue();

      expect(
        session.updates.last,
        const NowPlayingTransport(
          playing: true,
          position: Duration(seconds: 25),
          duration: Duration(seconds: 100),
        ),
      );
    });

    test('an unchanged state is not re-sent on every notify', () async {
      final controller = controllerFor();
      bind(controller);
      await controller.start();
      host.emitPosition(const Duration(seconds: 25));
      await pumpEventQueue();
      final sent = session.updates.length;

      // A notify that changes nothing the session shows: the volume slider.
      await controller.setVolume(0.5);
      await controller.setVolume(0.25);

      expect(session.updates, hasLength(sent));
    });

    test('the duration reaches the lock screen when mpv learns it', () async {
      // **The defect this was written for: nothing republished the metadata
      // for the file that was ALREADY playing.** mpv reports a duration a beat
      // after the open, `_metadata()` carries it, and the adapter turns a zero
      // into the platform's `null` — so keyed on the file index alone the
      // lock screen's scrubber had no length for the whole first file.
      final controller = controllerFor();
      bind(controller);
      await controller.start();

      expect(session.published.single.duration, Duration.zero);

      host.emitDuration(const Duration(seconds: 100));
      await pumpEventQueue();

      expect(session.published.last.duration, const Duration(seconds: 100));
      expect(session.published.last.title, 'Direct Play Movie');
    });

    test('disposing takes the session down with the screen', () async {
      final binder = bind(controllerFor());

      await binder.dispose();

      expect(session.cleared, 1);
    });

    test('a disposed binder stops following the player', () async {
      // `dispose`'s `removeListener` is what stops a torn-down screen's binder
      // publishing over a live one's — two player routes in a row share one
      // process-wide session. `just mutants` deleted that line and no test
      // objected, which is what this one is for.
      final controller = controllerFor();
      final binder = bind(controller);
      await controller.start();
      host.emitDuration(const Duration(seconds: 100));
      await pumpEventQueue();
      await binder.dispose();
      final published = session.published.length;
      final updates = session.updates.length;

      host
        ..emitPlaying(value: true)
        ..emitPosition(const Duration(seconds: 55));
      await pumpEventQueue();

      expect(session.published, hasLength(published));
      expect(session.updates, hasLength(updates));
    });
  });

  group('what the lock screen can ask for', () {
    test('pause reaches the engine', () async {
      final controller = controllerFor();
      bind(controller);
      await controller.start();
      host.emitPlaying(value: true);
      await pumpEventQueue();
      final before = host.calls.length;

      session.send(const PauseCommand());
      await pumpEventQueue();

      expect(host.calls.skip(before), contains('pause'));
    });

    test('pause on an already-paused player does NOT start it', () async {
      final controller = controllerFor();
      bind(controller);
      await controller.start();
      host.emitPlaying(value: false);
      await pumpEventQueue();
      final before = host.calls.length;

      session.send(const PauseCommand());
      await pumpEventQueue();

      expect(host.calls.skip(before), isNot(contains('play')));
    });

    test('play reaches the engine', () async {
      final controller = controllerFor();
      bind(controller);
      await controller.start();
      host.emitPlaying(value: false);
      await pumpEventQueue();
      final before = host.calls.length;

      session.send(const ResumeCommand());
      await pumpEventQueue();

      expect(host.calls.skip(before), contains('play'));
    });

    test('play on an already-playing player does NOT pause it', () async {
      final controller = controllerFor();
      bind(controller);
      await controller.start();
      host.emitPlaying(value: true);
      await pumpEventQueue();
      final before = host.calls.length;

      session.send(const ResumeCommand());
      await pumpEventQueue();

      expect(host.calls.skip(before), isNot(contains('pause')));
    });

    test('the lock screen scrubber seeks, and the seek is reported', () async {
      final controller = controllerFor();
      bind(controller);
      await controller.start();
      host
        ..emitDuration(const Duration(seconds: 100))
        ..emitPosition(const Duration(seconds: 10));
      await pumpEventQueue();

      session.send(const SeekCommand(Duration(seconds: 42)));
      await pumpEventQueue();

      expect(host.seeks, contains(const Duration(seconds: 42)));
      expect(api.reports.last.event, ProgressEvent.seek);
      expect(api.reports.last.position, 42.0);
    });

    test('a command after dispose reaches nothing', () async {
      final controller = controllerFor();
      final binder = bind(controller);
      await controller.start();
      host.emitPlaying(value: true);
      await pumpEventQueue();
      await binder.dispose();
      final before = host.calls.length;

      session.send(const PauseCommand());
      await pumpEventQueue();

      expect(host.calls, hasLength(before));
    });
  });

  group('the value types', () {
    // **Every field, one at a time, in both directions.** The first version
    // varied `subtitle` alone, and `just mutants` said so: the comparisons of
    // the other two fields could each be deleted with the suite still green,
    // which matters because `_publish`'s "has anything changed" rests entirely
    // on this `==`. A field left out of it is a lock screen that never
    // updates.
    test('metadata compares by value, field by field', () {
      const a = NowPlayingItem(
        title: 'A',
        subtitle: 'S1E1',
        duration: Duration(seconds: 3),
      );
      const same = NowPlayingItem(
        title: 'A',
        subtitle: 'S1E1',
        duration: Duration(seconds: 3),
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      for (final other in const [
        NowPlayingItem(
          title: 'B',
          subtitle: 'S1E1',
          duration: Duration(seconds: 3),
        ),
        NowPlayingItem(
          title: 'A',
          subtitle: 'S1E2',
          duration: Duration(seconds: 3),
        ),
        NowPlayingItem(
          title: 'A',
          subtitle: 'S1E1',
          duration: Duration(seconds: 4),
        ),
      ]) {
        expect(a, isNot(other), reason: '$other compared equal to $a');
      }
      expect(a, isNot('A'));
      expect(a.toString(), contains('S1E1'));
    });

    test('the transport compares by value, field by field', () {
      // The de-duplication in `_onChange` rests on this one, so a field
      // missing from it is a transport that stops moving on the lock screen
      // while the film plays. Same mutation finding as above.
      const a = NowPlayingTransport(
        playing: true,
        position: Duration(seconds: 1),
        duration: Duration(seconds: 2),
      );
      const same = NowPlayingTransport(
        playing: true,
        position: Duration(seconds: 1),
        duration: Duration(seconds: 2),
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      for (final other in const [
        NowPlayingTransport(
          playing: false,
          position: Duration(seconds: 1),
          duration: Duration(seconds: 2),
        ),
        NowPlayingTransport(
          playing: true,
          position: Duration(seconds: 9),
          duration: Duration(seconds: 2),
        ),
        NowPlayingTransport(
          playing: true,
          position: Duration(seconds: 1),
          duration: Duration(seconds: 9),
        ),
      ]) {
        expect(a, isNot(other), reason: '$other compared equal to $a');
      }
      expect(a, isNot('true'));
      expect(a.toString(), contains('true'));
    });

    test('every command is constructible at runtime, and says what it is', () {
      // **Through a tear-off, deliberately.** Every production use of the two
      // stateless commands is `const`, so a direct `const ResumeCommand()`
      // here would be canonicalised at compile time and their constructors
      // would never execute — which shows up as two uncovered lines against
      // `MAX_UNCOVERED=0`. Invoking the tear-off is a real call, and it is
      // also the assertion that matters: these are the values the adapter
      // hands across the port, and a command that cannot be built is a
      // transport button that does nothing.
      final built = [
        for (final make in <TransportCommand Function()>[
          ResumeCommand.new,
          PauseCommand.new,
        ])
          make(),
      ];

      expect(
        built.map((c) => c.toString()),
        ['ResumeCommand()', 'PauseCommand()'],
      );
      expect(
        const SeekCommand(Duration(seconds: 5)).toString(),
        contains('0:00:05'),
      );
    });
  });
}
