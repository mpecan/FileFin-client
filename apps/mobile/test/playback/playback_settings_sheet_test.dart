import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/playback_settings_sheet.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sheet that makes `wifiOnly` and `allowUnverifiedPlayback` writable.
///
/// Both are refusals `decide()` can return, and until this sheet existed
/// neither could be reached from a running path at all — only from a test
/// constructing a `SavedServer` by hand (§1, §5).
void main() {
  late List<(SavedServer, PlaybackPrefs)> changes;

  SavedServer server({
    bool wifiOnly = false,
    bool allowUnverifiedPlayback = false,
  }) => SavedServer(
    id: const ServerId('http://nas.local'),
    name: 'Attic NAS',
    baseUrl: Uri.parse('http://nas.local'),
    wifiOnly: wifiOnly,
    allowUnverifiedPlayback: allowUnverifiedPlayback,
  );

  setUp(() => changes = []);

  Future<void> pumpSheet(
    WidgetTester tester, {
    SavedServer? saved,
    PlaybackPrefs prefs = const PlaybackPrefs(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackSettingsSheet(
            server: saved ?? server(),
            prefs: prefs,
            onChanged: (s, p) => changes.add((s, p)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet names the server it is editing', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Playback on Attic NAS'), findsOneWidget);
    // The four rows, by the exact words on them. A `key` says which control a
    // test is driving and nothing about what a person reads, and these are the
    // whole interface: "Wi-Fi only" is F13's hard refusal and the other three
    // are the settings SPEC §7 names.
    expect(find.text('Wi-Fi only'), findsOneWidget);
    expect(find.text('Play over an unverified certificate'), findsOneWidget);
    expect(find.text('Ask before playing above'), findsOneWidget);
    expect(find.text('Save progress every'), findsOneWidget);
  });

  testWidgets('Wi-Fi only reflects the saved server and reports a change', (
    tester,
  ) async {
    await pumpSheet(tester, saved: server(wifiOnly: true));

    expect(
      tester.widget<SwitchListTile>(find.byKey(const Key('wifiOnly'))).value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('wifiOnly')));
    await tester.pumpAndSettle();

    expect(changes.single.$1.wifiOnly, isFalse);
    // The rest of the entry survives the edit: `copyWith` is what keeps the id
    // stable, and an id that moved would upsert a SECOND server rather than
    // replacing this one.
    expect(changes.single.$1.id, const ServerId('http://nas.local'));
    expect(changes.single.$1.name, 'Attic NAS');
    expect(
      tester.widget<SwitchListTile>(find.byKey(const Key('wifiOnly'))).value,
      isFalse,
      reason:
          'the switch shows the new value without waiting for a rebuild '
          'from whoever owns the settings file',
    );
  });

  testWidgets('the D10 toggle states exactly what enabling it gives up', (
    tester,
  ) async {
    await pumpSheet(tester);

    final subtitle = tester
        .widget<SwitchListTile>(
          find.byKey(const Key('allowUnverifiedPlayback')),
        )
        .subtitle;

    expect(subtitle, isA<Text>());
    final words = (subtitle! as Text).data!;
    // The cost, in the words D10 requires: the cookie, and the certificate
    // nobody checked. "Less secure" would be a summary of this rather than a
    // statement of it.
    expect(words, contains('session cookie'));
    expect(words, contains('certificate was never checked'));
    // And that the consequence is ONGOING, which is why it is a banner and not
    // a one-time dialog.
    expect(words, contains('banner'));
    expect(words, contains('the whole time'));
  });

  testWidgets('the D10 toggle reports the change it was flipped to', (
    tester,
  ) async {
    await pumpSheet(tester);

    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('allowUnverifiedPlayback')),
          )
          .value,
      isFalse,
      reason: 'D10 defaults to refuse',
    );

    await tester.tap(find.byKey(const Key('allowUnverifiedPlayback')));
    await tester.pumpAndSettle();

    expect(changes.single.$1.allowUnverifiedPlayback, isTrue);
    expect(changes.single.$1.wifiOnly, isFalse);
  });

  testWidgets('the size menu offers every choice, labelled for a person', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('meteredWarnBytes')));
    await tester.pumpAndSettle();

    // The exact labels, because the arithmetic that produces them is what a
    // mutation would change: `100 * 1000 * 1000` and `100 / 1000 / 1000` are
    // both "a number" and only one of them is 100 MB.
    for (final label in ['100 MB', '500 MB', '1.0 GB', '4.0 GB']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('picking a size reports it in bytes', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('meteredWarnBytes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.0 GB').last);
    await tester.pumpAndSettle();

    expect(changes.single.$2.meteredWarnBytes, 1000 * 1000 * 1000);
    expect(
      changes.single.$2.progressIntervalSecs,
      30,
      reason: 'the other half of the block is carried through untouched',
    );
  });

  testWidgets("the interval menu offers upstream's 30 among the four", (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('progressIntervalSecs')));
    await tester.pumpAndSettle();

    for (final label in ['10 s', '30 s', '60 s', '120 s']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('picking an interval reports it in seconds', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('progressIntervalSecs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('60 s').last);
    await tester.pumpAndSettle();

    expect(changes.single.$2.progressIntervalSecs, 60);
    expect(changes.single.$2.meteredWarnBytes, 500 * 1000 * 1000);
  });

  testWidgets('a value no menu offers is still shown, and still in order', (
    tester,
  ) async {
    // `settings.json` is a plain file a developer edits. A `DropdownButton`
    // whose `value` is absent from its `items` THROWS, so the union is what
    // stops a hand-edited file from crashing the screen that could fix it.
    await pumpSheet(
      tester,
      prefs: const PlaybackPrefs(
        progressIntervalSecs: 45,
        meteredWarnBytes: 12345,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('45 s'), findsOneWidget);
    expect(find.text('12 kB'), findsOneWidget);

    // Read the button's own `items` rather than opening the menu: both
    // dropdowns render their items into the same overlay, so a text finder
    // over an open menu cannot say which row an entry came from.
    final interval = tester.widget<DropdownButton<int>>(
      find.byKey(const Key('progressIntervalSecs')),
    );
    final size = tester.widget<DropdownButton<int>>(
      find.byKey(const Key('meteredWarnBytes')),
    );

    expect(interval.items!.map((i) => i.value), [10, 30, 45, 60, 120]);
    expect(size.items!.first.value, 12345, reason: 'sorted, so it leads');
    expect(size.items, hasLength(meteredWarnChoices.length + 1));
  });

  testWidgets('two edits report the whole state each time, not a delta', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('wifiOnly')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('allowUnverifiedPlayback')));
    await tester.pumpAndSettle();

    expect(changes, hasLength(2));
    // The second report still carries the first change. A sheet that rebuilt
    // from `widget.server` would silently undo it.
    expect(changes.last.$1.wifiOnly, isTrue);
    expect(changes.last.$1.allowUnverifiedPlayback, isTrue);
  });

  testWidgets('every control is a tappable target (M3 guidelines)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpSheet(tester);

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('showPlaybackSettings opens it as a modal sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPlaybackSettings(
                context,
                server: server(),
                prefs: const PlaybackPrefs(),
                onChanged: (s, p) => changes.add((s, p)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(PlaybackSettingsSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('wifiOnly')));
    await tester.pumpAndSettle();

    expect(changes.single.$1.wifiOnly, isTrue);
  });
}
