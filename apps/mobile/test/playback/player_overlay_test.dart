import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_controls.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dpad.dart';
import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

/// The overlay the redesign made the ONE set of controls, at both its sizes.
///
/// Until this milestone there were two: a D-pad overlay built inside
/// `RealMpvPlayer.buildSurface`, which is what shipped, and `PlayerControls`,
/// which is what every widget test drove through a fake host. Neither was
/// covered by the other's assertions. These cases are about the properties
/// that differ between a phone and a television, which is the whole of what
/// [PlayerControlsMetrics] carries.
void main() {
  const id = MediaId('e4285edb34d5');

  late FakeLibraryApi api;
  late FakePlaybackHost host;
  late PlayerController controller;

  PlayerController build({int files = 2, int initial = 1}) => PlayerController(
    api: api,
    host: host,
    network: FakeNetworkStatus(),
    detail: MediaDetail(
      id: id,
      title: 'Fawlty Towers',
      files: [
        for (var i = 0; i < files; i += 1)
          FileInfo(index: FileIndex(i), name: 'S1E$i', ext: '.avi'),
      ],
    ),
    server: SavedServer(
      id: const ServerId('a'),
      name: 'Attic NAS',
      baseUrl: Uri.parse('http://nas.local'),
    ),
    prefs: const PlaybackPrefs(),
    initialFile: FileIndex(initial),
    startAt: Duration.zero,
  );

  setUp(() {
    api = FakeLibraryApi()
      ..playbackHeadersResult = const PlaybackSessionHeaders({'Cookie': 'x'});
    host = FakePlaybackHost();
    controller = build();
    addTearDown(controller.dispose);
  });

  Future<void> show(
    WidgetTester tester, {
    PlayerControlsMetrics metrics = PlayerControlsMetrics.phone,
    VoidCallback? onBack,
  }) async {
    await controller.start();
    await pumpTv(
      tester,
      Scaffold(
        body: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => PlayerControls(
            controller: controller,
            title: 'Fawlty Towers',
            facts: 'S1E1 · avi · direct play',
            metrics: metrics,
            onBack: onBack,
            onShowAudio: () {},
            onShowSubtitles: () {},
          ),
        ),
      ),
    );
  }

  /// The lock exists so a pocket or a sleeve cannot scrub a film. Everything
  /// else goes; the padlock stays, or there is no way back.
  testWidgets('locking hides every control except the padlock', (
    tester,
  ) async {
    await show(tester);
    expect(find.byTooltip('Lock controls'), findsOneWidget);

    await tester.tap(find.byTooltip('Lock controls'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Unlock controls'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsNothing);
    expect(find.byTooltip('Back 10 seconds'), findsNothing);
    expect(find.text('Fawlty Towers'), findsNothing);
  });

  testWidgets('unlocking brings them all back', (tester) async {
    await show(tester);

    await tester.tap(find.byTooltip('Lock controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unlock controls'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.text('Fawlty Towers'), findsOneWidget);
  });

  /// Ten seconds each way, which is the interval the design's own hint strip
  /// states. Asserted as a seek to a POSITION rather than as a call count: a
  /// button that seeks the wrong way looks identical from the outside.
  testWidgets('the two seek buttons move ten seconds each way', (
    tester,
  ) async {
    await show(tester);
    host.emitPosition(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Forward 10 seconds'));
    await tester.pumpAndSettle();
    expect(host.seeks.last, const Duration(seconds: 70));

    // 60, not 50: the controller adopts the position it just seeked to, so
    // the second press is ten seconds back from 70 rather than from where the
    // engine last reported. That is the behaviour a user sees on a double tap.
    await tester.tap(find.byTooltip('Back 10 seconds'));
    await tester.pumpAndSettle();
    expect(host.seeks.last, const Duration(seconds: 60));
  });

  /// mpv reports a duration of zero for a stream it has not finished reading,
  /// so an upper clamp would refuse every forward seek in the first moments of
  /// an HLS playlist — exactly when a user skips a title sequence.
  group('the seek target', () {
    test('never lands before the start', () {
      expect(
        PlayerTransport.seekTarget(
          const Duration(seconds: 3),
          -PlayerTransport.step,
        ),
        Duration.zero,
      );
    });

    test('is not clamped at the end, because the end may be unknown', () {
      expect(
        PlayerTransport.seekTarget(
          const Duration(hours: 9),
          PlayerTransport.step,
        ),
        const Duration(hours: 9, seconds: 10),
      );
    });
  });

  /// A D-pad has no drag, so left and right on the scrubber are the seek —
  /// which is what the television's own hint strip promises.
  testWidgets('left and right on the scrubber seek by ten seconds', (
    tester,
  ) async {
    await show(tester, metrics: PlayerControlsMetrics.tv);
    host
      ..emitDuration(const Duration(minutes: 30))
      ..emitPosition(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    await dpadFocus(tester, 'Seek');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(host.seeks.last, const Duration(seconds: 70));
  });

  testWidgets('dragging the scrubber seeks once, when the finger lifts', (
    tester,
  ) async {
    await show(tester);
    host.emitDuration(const Duration(minutes: 10));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Slider).first, const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(host.seeks, hasLength(1));
  });

  /// A negative duration — which mpv can report for a stream it has not
  /// finished reading — threw `ArgumentError` out of `build` before the guard.
  testWidgets('a negative duration does not take the screen down', (
    tester,
  ) async {
    await show(tester);
    host.emitDuration(const Duration(seconds: -1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Slider), findsWidgets);
  });

  testWidgets('the file pills appear only when there is a file to go to', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Previous'), findsOneWidget);
    expect(find.text('Next'), findsNothing);

    controller.dispose();
    controller = build(files: 1, initial: 0);
    await show(tester);

    expect(find.text('Previous'), findsNothing);
    expect(find.text('Next'), findsNothing);
  });

  /// A television remote has its own volume keys wired to the set's
  /// amplifier, so a second slider that moves only mpv's gain is a control
  /// that appears not to work. The phone has no such keys.
  testWidgets('the volume slider is on the phone and not on the television', (
    tester,
  ) async {
    // Counted as sliders rather than as the speaker glyph, which the audio
    // pill carries too: two on a phone (the scrubber and the volume) against
    // one on a television.
    await show(tester);
    expect(find.byType(Slider), findsNWidgets(2));

    await show(tester, metrics: PlayerControlsMetrics.tv);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.textContaining('OK pause'), findsOneWidget);
  });

  testWidgets('the volume slider drives the engine, not a literal', (
    tester,
  ) async {
    await show(tester);

    await tester.drag(find.byType(Slider).last, const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(host.calls.where((c) => c.startsWith('setVolume')), isNotEmpty);
    expect(controller.volume, lessThan(1.0));
  });

  /// The phone shows no key hints and the television does, and that asymmetry
  /// is the design's: a finger discovers a control by touching it, a D-pad
  /// cannot.
  testWidgets('the key hints are a television thing only', (tester) async {
    await show(tester);
    expect(find.textContaining('◀▶ seek'), findsNothing);

    await show(tester, metrics: PlayerControlsMetrics.tv);
    expect(find.textContaining('◀▶ seek 10s'), findsOneWidget);
  });

  testWidgets('the audio pill names the track once one has been chosen', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Audio'), findsOneWidget);

    await controller.selectAudio(
      const PlaybackTrackRef(id: '2', label: 'Japanese'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Japanese'), findsOneWidget);
    expect(find.text('Audio'), findsNothing);
  });

  testWidgets('the subtitle pill says Off until one is chosen', (
    tester,
  ) async {
    await show(tester);
    expect(find.text('Off'), findsOneWidget);

    await controller.selectSubtitle(
      const SubtitleSource(
        index: SubtitleIndex(1),
        label: 'Slovenian',
        data: 'WEBVTT',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Slovenian'), findsOneWidget);
  });

  testWidgets('back is offered only when there is somewhere to go', (
    tester,
  ) async {
    await show(tester);
    expect(find.byTooltip('Back'), findsNothing);

    var left = 0;
    await show(tester, onBack: () => left += 1);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(left, 1);
  });

  /// Hidden controls must not be tappable: a tap on an invisible pause button
  /// is a tap the user did not know they were making.
  testWidgets('the controls fade, and a tap brings them back', (tester) async {
    await show(tester);

    await tester.pump(PlayerControls.fadeAfter + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0.0,
    );

    await tester.tapAt(tester.getCenter(find.byType(PlayerControls)));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1.0,
    );
  });

  /// Every control on the television overlay, reachable with the four arrows
  /// and nothing else — a remote has no other way to get to any of them.
  testWidgets('every TV control is reachable by D-pad', (tester) async {
    await show(tester, metrics: PlayerControlsMetrics.tv, onBack: () {});

    final reached = await dpadReachable(tester);

    expect(
      reached,
      containsAll([
        'Back',
        'Audio',
        'Off',
        'Lock controls',
        'Play',
        'Back 10 seconds',
        'Forward 10 seconds',
        'Previous',
      ]),
    );
  });

  /// `previous()` is `next()`'s mirror and nothing exercised it: the pill was
  /// drawn, the guard was written, and the whole path from press to reopen was
  /// shipped unrun.
  testWidgets('Previous stops, steps back a file and reopens', (tester) async {
    await show(tester);
    host
      // A duration as well as a position: the progress reporter refuses to
      // send anything without a usable one, so a stop report needs both.
      ..emitDuration(const Duration(minutes: 30))
      ..emitPosition(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    final before = host.opened.length;

    await dpadActivate(tester, 'Previous');
    await tester.pumpAndSettle();

    expect(controller.current, const FileIndex(0));
    // A reopen, not merely a pointer move: the engine has to be given the new
    // file or the screen shows a new title over the old picture.
    expect(host.opened, hasLength(before + 1));
    // The URL is what says which file: a  that stepped the pointer
    // and reopened the SAME file is a bug no position assertion would see.
    expect(host.opened.last.url.path, endsWith('/file/0'));
  });

  /// The guard, in the direction that matters: pressing back on the first file
  /// must not step to -1.
  testWidgets('Previous is not offered on the first file', (tester) async {
    controller.dispose();
    controller = build(initial: 0);
    await show(tester);

    expect(find.text('Previous'), findsNothing);
    expect(find.text('Next'), findsOneWidget);
  });

  /// A tap and a centre press are two paths into the same button, and only one
  /// of them was exercised. On a television only the second exists.
  testWidgets('the centre button plays and pauses', (tester) async {
    await show(tester, metrics: PlayerControlsMetrics.tv);

    await dpadActivate(tester, 'Play');
    await tester.pumpAndSettle();
    expect(host.calls, contains('play'));

    host.emitPlaying(value: true);
    await tester.pumpAndSettle();
    await dpadActivate(tester, 'Pause');
    await tester.pumpAndSettle();
    expect(host.calls, contains('pause'));
  });

  /// **A television has nothing to tap.** The overlay fades after five seconds
  /// and `ExcludeFocus` then takes every control out of traversal, so on a
  /// phone you touch the glass and on a TV you are left with a playing film
  /// and no way to pause it. Any key has to wake it.
  testWidgets('on a television any key brings the faded controls back', (
    tester,
  ) async {
    await show(tester, metrics: PlayerControlsMetrics.tv);
    expect(find.byTooltip('Play'), findsOneWidget);

    await tester.pump(PlayerControls.fadeAfter + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      0.0,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
      1.0,
    );
  });

  /// The waking press must not ALSO act. A remote user pressing down to see
  /// the controls has not asked to seek, and a press that did both would move
  /// the film before they could see where they were.
  testWidgets('the waking press does nothing but wake', (tester) async {
    await show(tester, metrics: PlayerControlsMetrics.tv);
    await tester.pump(PlayerControls.fadeAfter + const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // A snapshot, because starting playback has already issued a `play`: what
    // is being pinned is that the waking press adds nothing.
    final before = [...host.calls];
    await tester.sendKeyEvent(dpadSelect);
    await tester.pumpAndSettle();

    expect(host.calls, before);
  });

  /// And once awake, the keys work normally again — a wake handler that kept
  /// swallowing presses would be the same dead end with an extra frame.
  testWidgets('after waking, the D-pad drives the controls again', (
    tester,
  ) async {
    await show(tester, metrics: PlayerControlsMetrics.tv);
    await tester.pump(PlayerControls.fadeAfter + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    await dpadActivate(tester, 'Play');
    await tester.pumpAndSettle();

    expect(host.calls, contains('play'));
  });
}
