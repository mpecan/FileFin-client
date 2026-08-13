import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

/// The two track sheets: which row they tick, and that they close.
///
/// Split from `player_controls_test.dart` for `just file-size`'s 600-line hard
/// limit. Both properties are the picker's rather than the overlay's, and both
/// were mutable with the whole suite green — the tick because nothing read it,
/// the close because the choice still reached the engine either way.
void main() {
  const id = MediaId('e4285edb34d5');

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
        id: id,
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
        id: const ServerId('a'),
        name: 'Attic NAS',
        baseUrl: Uri.parse('http://nas.local'),
      ),
      prefs: const PlaybackPrefs(),
      initialFile: const FileIndex(0),
      startAt: Duration.zero,
    );
    addTearDown(controller.dispose);
  });

  /// Pumps a bare scaffold whose one button opens [picker].
  ///
  /// The pickers are the PAGE's, not the overlay's: a sheet needs a
  /// `Navigator`, and `PlayerControls` only reports that its pill was pressed.
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

  /// **A picker that ticks the wrong row is a picker that lies**, and nothing
  /// asserted the tick: `just mutants` inverted all three `selected:` tests —
  /// audio, Off, and each sidecar — and the suite stayed green. On a
  /// television, where the sheet is walked with a D-pad and there is no
  /// pointer to hover, the tick is the only thing saying what is playing.
  ListTile tileFor(WidgetTester tester, String label) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, label));

  testWidgets('the audio sheet ticks the chosen track, and only it', (
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
    await controller.selectAudio(
      const PlaybackTrackRef(id: '2', label: 'Japanese'),
    );
    await openPicker(tester, showAudioPicker);

    expect(tileFor(tester, 'Japanese').selected, isTrue);
    expect(tileFor(tester, 'English').selected, isFalse);
  });

  testWidgets('the subtitle sheet ticks Off when subtitles are off', (
    tester,
  ) async {
    await controller.start();
    // Explicitly, rather than trusting the state `start()` leaves behind: the
    // controller picks a default sidecar when the item has one, so "no
    // selection" is a state a test has to ask for.
    await controller.selectSubtitle(null);
    await openPicker(tester, showSubtitlePicker);

    expect(tileFor(tester, 'Off').selected, isTrue);
    expect(tileFor(tester, 'English').selected, isFalse);
    expect(tileFor(tester, 'Slovenian').selected, isFalse);
  });

  testWidgets('choosing a sidecar moves the tick off Off and onto it', (
    tester,
  ) async {
    await controller.start();
    await openPicker(tester, showSubtitlePicker);
    await tester.tap(find.text('Slovenian'));
    await tester.pumpAndSettle();
    await openPicker(tester, showSubtitlePicker);

    expect(tileFor(tester, 'Slovenian').selected, isTrue);
    expect(tileFor(tester, 'Off').selected, isFalse);
    expect(tileFor(tester, 'English').selected, isFalse);
  });

  /// **A picker that does not close is a picker that traps you**, and on a
  /// television there is nothing to tap outside it: `just mutants` deleted all
  /// three `Navigator.pop(sheet)` calls with the suite green. The choice would
  /// still reach the engine — which is why the existing cases pass — while the
  /// sheet stayed over the film.
  testWidgets('choosing an audio track closes the sheet', (tester) async {
    await controller.start();
    host.emitTracks(
      const PlaybackTracks(
        audio: [PlaybackTrackRef(id: '1', label: 'English')],
      ),
    );
    await openPicker(tester, showAudioPicker);

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('choosing a sidecar closes the sheet', (tester) async {
    await controller.start();
    await openPicker(tester, showSubtitlePicker);

    await tester.tap(find.text('Slovenian'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('choosing Off closes the sheet', (tester) async {
    await controller.start();
    await openPicker(tester, showSubtitlePicker);

    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
  });
}
