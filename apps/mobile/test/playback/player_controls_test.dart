import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_controls.dart';
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

const _id = MediaId('e4285edb34d5');
final Uri _url = Uri.parse('http://nas.local/api/media/e4285edb34d5/file/0');

void main() {
  late FakeLibraryApi api;
  late FakePlaybackHost host;
  late PlayerController controller;

  setUp(() {
    api = FakeLibraryApi()
      ..playbackHeadersResult = const PlaybackSessionHeaders({'Cookie': 'x'})
      ..subtitleResult = 'WEBVTT\n\n';
    host = FakePlaybackHost();
    controller = PlayerController(
      api: api,
      host: host,
      network: FakeNetworkStatus(),
      detail: const MediaDetail(
        id: _id,
        title: 'Film',
        files: [
          FileInfo(
            subtitles: [
              SubtitleInfo(label: 'English'),
              SubtitleInfo(index: SubtitleIndex(1), label: 'Slovenian'),
            ],
          ),
        ],
      ),
      server: SavedServer(
        id: const ServerId('home'),
        name: 'Home',
        baseUrl: Uri.parse('http://nas.local'),
      ),
      prefs: const PlaybackPrefs(),
      initialFile: const FileIndex(0),
      startAt: Duration.zero,
    );
    addTearDown(controller.dispose);
  });

  Future<void> pumpControls(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // `PlayerControls` is stateless and `PlayerPage` is what rebuilds it
          // on the controller's notification; this stands in for that so the
          // controls can be driven without the whole screen.
          body: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => PlayerControls(
              controller: controller,
              title: 'Direct Play Movie',
              facts: 'mp4 · direct play',
              metrics: PlayerControlsMetrics.phone,
              onShowAudio: () {},
              onShowSubtitles: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Pumps a bare scaffold whose one button opens [picker].
  ///
  /// The two track pickers are the PAGE's, not the controls': a sheet needs a
  /// `Navigator`, and `PlayerControls` only reports that its pill was pressed.
  /// Driving them straight rather than through `PlayerPage` keeps these cases
  /// about the sheet rather than about the whole screen.
  Future<void> openPicker(
    WidgetTester tester,
    Future<void> Function(BuildContext, PlayerController) picker,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(picker(context, controller)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the audio picker says so when the engine reported none', (
    tester,
  ) async {
    // `start()` is what registers the stream listeners, so nothing the engine
    // emits reaches the controller before it. An empty sheet would be a tap
    // that opens nothing and explains nothing; a disabled row says which.
    await controller.start();
    await openPicker(tester, showAudioPicker);
    expect(find.text('No audio tracks reported'), findsOneWidget);
  });

  testWidgets('the audio picker lists what the engine did report', (
    tester,
  ) async {
    await controller.start();
    host.emitTracks(
      const PlaybackTracks(
        audio: [
          PlaybackTrackRef(id: '1', label: 'English'),
          PlaybackTrackRef(id: '2', label: 'Japanese'),
        ],
      ),
    );
    await openPicker(tester, showAudioPicker);

    expect(find.text('No audio tracks reported'), findsNothing);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Japanese'), findsOneWidget);
  });

  testWidgets('picking an audio track passes libmpv its own id', (
    tester,
  ) async {
    await controller.start();
    host.emitTracks(
      const PlaybackTracks(
        audio: [
          PlaybackTrackRef(id: '1', label: 'English'),
          PlaybackTrackRef(id: '2', label: 'Japanese'),
        ],
      ),
    );
    await openPicker(tester, showAudioPicker);

    await tester.tap(find.text('Japanese'));
    await tester.pumpAndSettle();

    expect(host.calls, contains('selectAudioTrack(2)'));
    // And the overlay's pill now says which, which is the whole reason the
    // design replaced an icon-only menu with a named one.
    expect(audioLabel(controller), 'Japanese');
  });

  testWidgets('the subtitle menu offers Off and every sidecar', (tester) async {
    await controller.start();
    await openPicker(tester, showSubtitlePicker);

    expect(find.text('Off'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Slovenian'), findsOneWidget);

    await tester.tap(find.text('Slovenian'));
    await tester.pumpAndSettle();

    expect(host.subtitles.last?.index, const SubtitleIndex(1));
  });

  testWidgets('Off turns subtitles off rather than picking one', (
    tester,
  ) async {
    await controller.start();
    await openPicker(tester, showSubtitlePicker);
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();

    expect(host.subtitles.last, isNull);
    expect(controller.subtitle, isNull);
  });

  testWidgets('play/pause toggles, and the icon says which', (tester) async {
    await controller.start();
    await pumpControls(tester);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();
    expect(host.calls, contains('play'));

    host.emitPlaying(value: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pumpAndSettle();

    expect(host.calls, contains('pause'));
  });

  /// The scrubber, which is `Slider.first` — the volume one is second.
  Slider scrubber(WidgetTester tester) =>
      tester.widget<Slider>(find.byType(Slider).first);

  testWidgets('before a duration arrives the scrubber is inert, not at zero', (
    tester,
  ) async {
    // `Duration.zero` is what `PlayerController` reports until mpv has read the
    // header, and it is a real state a user sees for a moment on every open —
    // not an edge case. A `Slider` with `max: 0` is a degenerate widget that
    // Flutter accepts without complaint, so nothing throws and only an
    // assertion can notice: `max` falls back to 1 and BOTH callbacks are null,
    // so a stray tap cannot seek a file whose length is not known yet.
    await controller.start();
    await pumpControls(tester);

    expect(controller.duration, Duration.zero);
    expect(scrubber(tester).max, 1);
    expect(scrubber(tester).value, 0);
    expect(scrubber(tester).onChanged, isNull);
    expect(scrubber(tester).onChangeEnd, isNull);
  });

  testWidgets('a nonsensical duration disables the scrubber too', (
    tester,
  ) async {
    // The guard is `<= 0` rather than `== 0`, and this is the input that makes
    // the difference observable. mpv reports a duration for a stream it has not
    // finished reading, and a negative one reaching `Slider.max` is an
    // assertion failure inside Flutter — it requires `min <= max`. Refusing
    // anything at or below zero is one branch instead of two.
    await controller.start();
    host.emitDuration(const Duration(seconds: -1));
    await pumpControls(tester);

    expect(controller.duration, const Duration(seconds: -1));
    expect(scrubber(tester).max, 1);
    expect(scrubber(tester).onChanged, isNull);
    expect(scrubber(tester).onChangeEnd, isNull);
  });

  testWidgets('a real duration enables the scrubber and scales it', (
    tester,
  ) async {
    await controller.start();
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 20));
    await pumpControls(tester);

    expect(scrubber(tester).max, 100000);
    expect(scrubber(tester).value, 20000);
    expect(scrubber(tester).onChanged, isNotNull);
    expect(scrubber(tester).onChangeEnd, isNotNull);
    // `onChangeEnd`, never `onChanged`: a scrubber that reported on every frame
    // of a drag would post a request per pixel.
    scrubber(tester).onChangeEnd!(42000);
    await tester.pumpAndSettle();
    expect(host.seeks, [const Duration(seconds: 42)]);
    expect(
      host.calls.where((c) => c.startsWith('seek')),
      hasLength(1),
      reason: 'onChanged is a no-op and must not seek',
    );
  });

  testWidgets('a position past the duration is clamped, not out of range', (
    tester,
  ) async {
    // mpv's last position tick can land past the duration it reported, and a
    // `Slider.value` outside `[min, max]` is an assertion failure rather than a
    // clipped thumb.
    await controller.start();
    host
      ..emitDuration(const Duration(seconds: 3))
      ..emitPosition(const Duration(seconds: 4));
    await pumpControls(tester);

    expect(scrubber(tester).value, 3000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the FIRST sidecar is selectable, not read as Off', (
    tester,
  ) async {
    // Index 0 is the boundary the menu's `index < 0` guard sits on: with `<=`
    // the first subtitle in every list silently turns subtitles off instead,
    // and the two other subtitle tests — which tap `Slovenian` (index 1) and
    // `Off` (-1) — both still pass.
    await controller.start();
    await pumpControls(tester);

    await tester.tap(find.byIcon(Icons.subtitles));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(host.subtitles.last, isNotNull);
    expect(host.subtitles.last?.index, const SubtitleIndex(0));
    expect(controller.subtitle?.label, 'English');
  });

  testWidgets('the volume slider reaches the engine AND shows where it is', (
    tester,
  ) async {
    await pumpControls(tester);
    Slider volume() => tester.widget<Slider>(find.byType(Slider).last);
    expect(volume().value, 1.0);

    await tester.drag(find.byType(Slider).last, const Offset(-100, 0));
    await tester.pumpAndSettle();

    expect(host.calls.where((c) => c.startsWith('setVolume')), isNotEmpty);
    // M4.R/P6: `value:` was the literal `1`, so the thumb snapped back to full
    // on the next rebuild while mpv held the dragged value — and mutating that
    // literal to `0` left all 149 playback tests green.
    expect(controller.volume, lessThan(1.0));
    expect(volume().value, controller.volume);
  });

  // M4.R/T9. `itemBuilder` numbers ONE snapshot of `controller.subtitles`;
  // `onSelected` reads a LATER one. `PlayerController._open()` replaces the
  // list wholesale — on `next()`, and asynchronously from `_recover()` on any
  // mpv error — so a menu built over two sidecars and left open across an
  // advance indexes past the end on its last row and throws a `RangeError` out
  // of a callback. Same shape as the clamp-before-guard bug: a value computed
  // against one state, applied to another.
  //
  // **Both sides of the boundary, and `just mutants` is why there are two.**
  // With only the "one shorter" case `index >= length` and `index > length`
  // answer alike; with only the "gone entirely" case `>=` and `==` do. Neither
  // test alone pins the operator.
  void useShowWhoseNextFileHas(List<SubtitleInfo> subtitles) {
    controller.dispose();
    controller = PlayerController(
      api: api,
      host: host,
      network: FakeNetworkStatus(),
      detail: MediaDetail(
        id: _id,
        title: 'Show',
        files: [
          const FileInfo(
            subtitles: [
              SubtitleInfo(label: 'English'),
              SubtitleInfo(index: SubtitleIndex(1), label: 'Slovenian'),
            ],
          ),
          FileInfo(index: const FileIndex(1), subtitles: subtitles),
        ],
      ),
      server: SavedServer(
        id: const ServerId('home'),
        name: 'Home',
        baseUrl: Uri.parse('http://nas.local'),
      ),
      prefs: const PlaybackPrefs(),
      initialFile: const FileIndex(0),
      startAt: Duration.zero,
    );
    addTearDown(controller.dispose);
  }

  Future<void> tapSlovenianAcrossAnAdvance(WidgetTester tester) async {
    await controller.start();
    await openPicker(tester, showSubtitlePicker);
    expect(find.text('Slovenian'), findsOneWidget);

    await controller.next();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Slovenian'));
    await tester.pumpAndSettle();
  }

  testWidgets('a subtitle row one past the shortened list turns them off', (
    tester,
  ) async {
    // Tapped index EQUALS the new length: 1 into a list of 1.
    useShowWhoseNextFileHas(const [SubtitleInfo(label: 'English')]);

    await tapSlovenianAcrossAnAdvance(tester);

    expect(controller.subtitles, hasLength(1));
    expect(tester.takeException(), isNull);
    expect(controller.subtitle, isNull);
  });

  testWidgets('a subtitle row well past the emptied list turns them off', (
    tester,
  ) async {
    // Tapped index EXCEEDS the new length: 1 into a list of 0.
    useShowWhoseNextFileHas(const []);

    await tapSlovenianAcrossAnAdvance(tester);

    expect(controller.subtitles, isEmpty);
    expect(tester.takeException(), isNull);
    expect(controller.subtitle, isNull);
  });

  testWidgets('NF6 — hidden and inactive both report, resumed does not', (
    tester,
  ) async {
    await controller.start();
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 20));
    await tester.pumpAndSettle();

    host.emitPosition(const Duration(seconds: 25));
    await tester.pumpAndSettle();
    await controller.handleLifecycle(AppLifecycleState.inactive);
    expect(api.reports.last.event, ProgressEvent.pause);

    host.emitPosition(const Duration(seconds: 55));
    await tester.pumpAndSettle();
    await controller.handleLifecycle(AppLifecycleState.hidden);
    expect(api.reports.last.position, 55.0);
  });

  testWidgets('NF6 — detached is not one of the three that report', (
    tester,
  ) async {
    // The guard names `paused`, `inactive` and `hidden` and deliberately stops
    // there. `detached` is the app being torn down: both platforms send
    // `paused` first, so the pointer this milestone cares about is already
    // written, and reporting again for an app that is going away buys nothing.
    //
    // Asserting it is what makes the LIST the contract. Widening the third
    // disjunct to "anything that is not hidden" — which is one operator — reads
    // as a harmless generalisation and passes every other lifecycle test here.
    await controller.start();
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    // 15 seconds on, which is under the 30-second interval, so no checkpoint
    // fires and a `pause` here is a NEW second rather than a deduped one.
    host.emitPosition(const Duration(seconds: 55));
    await tester.pumpAndSettle();
    final reportsBefore = api.reports.length;
    final pausesBefore = host.calls.where((c) => c == 'pause').length;

    await controller.handleLifecycle(AppLifecycleState.detached);
    await controller.handleLifecycle(AppLifecycleState.resumed);

    expect(api.reports, hasLength(reportsBefore));

    await controller.handleLifecycle(AppLifecycleState.paused);

    expect(api.reports, hasLength(reportsBefore + 1));
    expect(api.reports.last.position, 55.0);
    expect(api.reports.last.event, ProgressEvent.pause);
    // F14: none of the four touched the engine. Backgrounding reports and
    // leaves playback alone; `mpv_player.dart`'s
    // `pauseUponEnteringBackgroundMode: false` is the other half of it.
    expect(host.calls.where((c) => c == 'pause'), hasLength(pausesBefore));
  });

  group('describeApiFailure — the player says one line, not a panel', () {
    test('each arm reads as a sentence a person can act on', () {
      expect(describeApiFailure(SessionExpired(_url)).$2, isTrue);
      expect(
        describeApiFailure(BadRequest(_url, 'bad file index')).$1,
        contains('bad file index'),
      );
      expect(
        describeApiFailure(NotFound(_url)).$1,
        contains('not on the server'),
      );
      expect(
        describeApiFailure(ConnectionFailed(_url)).$1,
        contains('could not start'),
      );
      expect(describeApiFailure(ConnectionFailed(_url)).$2, isFalse);
    });
  });

  /// An empty sheet would be a tap that opens nothing and explains nothing.
  /// The API lists sidecars and this item has none.
  testWidgets('the subtitle picker says so when there are no sidecars', (
    tester,
  ) async {
    controller.dispose();
    controller = PlayerController(
      api: api,
      host: host,
      network: FakeNetworkStatus(),
      detail: const MediaDetail(id: _id, title: 'Film', files: [FileInfo()]),
      server: SavedServer(
        id: const ServerId('a'),
        name: 'Attic NAS',
        baseUrl: Uri.parse('http://nas.local'),
      ),
      prefs: const PlaybackPrefs(),
      initialFile: const FileIndex(0),
      startAt: Duration.zero,
    );
    addTearDown(controller.dispose);
    await controller.start();

    await openPicker(tester, showSubtitlePicker);

    expect(find.text('No subtitles available'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
  });
}
