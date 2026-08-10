import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/now_playing.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_controls.dart';
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_now_playing.dart';
import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

const _id = MediaId('e4285edb34d5');

MediaDetail _detail({int files = 1, int size = 10}) => MediaDetail(
  id: _id,
  title: 'Direct Play Movie',
  files: [
    for (var i = 0; i < files; i++)
      FileInfo(index: FileIndex(i), size: size, name: 'File $i'),
  ],
);

SavedServer _server({
  bool wifiOnly = false,
  bool allowUnverifiedPlayback = false,
}) => SavedServer(
  id: const ServerId('home'),
  name: 'Home NAS',
  baseUrl: Uri.parse('http://nas.local'),
  wifiOnly: wifiOnly,
  allowUnverifiedPlayback: allowUnverifiedPlayback,
);

void main() {
  late FakeLibraryApi api;
  late FakePlaybackHost host;
  late FakeNetworkStatus network;

  setUp(() {
    api = FakeLibraryApi()
      ..playbackHeadersResult = const PlaybackSessionHeaders({
        'Cookie': 'filefin_session=sess-1',
      })
      ..meResult = const AuthResult(user: 'sam');
    host = FakePlaybackHost();
    network = FakeNetworkStatus();
  });

  Future<void> pumpPlayer(
    WidgetTester tester, {
    MediaDetail? detail,
    SavedServer? server,
    VoidCallback? onSignIn,
    Future<NowPlayingHost> Function()? nowPlayingFactory,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          api: api,
          hostFactory: () => host,
          nowPlayingFactory: nowPlayingFactory ?? fakeNowPlayingFactory(),
          network: network,
          detail: detail ?? _detail(),
          server: server ?? _server(),
          prefs: const PlaybackPrefs(),
          initialFile: const FileIndex(0),
          startAt: Duration.zero,
          onSignIn: onSignIn,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the surface comes from the HOST, so no Video is ever built', (
    tester,
  ) async {
    // The whole reason `buildSurface` is on the port. `VideoController` does
    // construct headlessly (M4.R/G1 re-measured it) — but the `Player` it
    // attaches to can then never be DISPOSED under `flutter test`, and a
    // screen test disposes its host on every teardown.
    await pumpPlayer(tester);

    expect(find.byKey(const ValueKey('fake-surface')), findsOneWidget);
    expect(host.calls, contains('buildSurface'));
  });

  testWidgets('the title and the transport controls are on screen', (
    tester,
  ) async {
    await pumpPlayer(tester);
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 42))
      ..emitPlaying(value: true);
    await tester.pumpAndSettle();

    expect(find.text('Direct Play Movie'), findsOneWidget);
    expect(find.text('0:42'), findsOneWidget);
    expect(find.text('1:40'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('the scrubber reports on release, never during the drag', (
    tester,
  ) async {
    await pumpPlayer(tester);
    host.emitDuration(const Duration(seconds: 100));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Slider).first, const Offset(80, 0));
    await tester.pumpAndSettle();

    // One seek from the release, and one report — not one per frame of the
    // drag, which would be a request per pixel.
    expect(host.seeks, hasLength(1));
    expect(
      api.reports.where((r) => r.event == ProgressEvent.seek),
      hasLength(1),
    );
  });

  testWidgets('Next is disabled on a single-file item', (tester) async {
    await pumpPlayer(tester);

    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.skip_next),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Next opens the following file, at zero', (tester) async {
    await pumpPlayer(tester, detail: _detail(files: 2));

    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.skip_next),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithIcon(IconButton, Icons.skip_next));
    await tester.pumpAndSettle();

    // We advance ourselves rather than through mpv's playlist, so that "which
    // file is playing" — the key every progress report carries — has one
    // source of truth.
    expect(host.opened.last.url.path, '/api/media/e4285edb34d5/file/1');
    expect(host.opened.last.startAt, Duration.zero);
  });

  testWidgets('F13 — a metered refusal explains itself and plays nothing', (
    tester,
  ) async {
    network.answer = NetworkType.metered;

    await pumpPlayer(tester, server: _server(wifiOnly: true));

    expect(find.textContaining('Wi-Fi only'), findsOneWidget);
    expect(find.textContaining('Home NAS'), findsOneWidget);
    expect(host.opened, isEmpty);
    // The refusal replaces the player entirely; there is nothing to control.
    expect(find.byType(PlayerControls), findsNothing);
  });

  testWidgets('F13 — the size prompt names the real size, and Play proceeds', (
    tester,
  ) async {
    network.answer = NetworkType.metered;

    await pumpPlayer(tester, detail: _detail(size: 900 * 1000 * 1000));

    expect(find.textContaining('900 MB'), findsOneWidget);
    expect(host.opened, isEmpty);

    await tester.tap(find.text('Play anyway'));
    await tester.pumpAndSettle();

    expect(host.opened, hasLength(1));
  });

  testWidgets('D10 — the unverified-playback banner is PERSISTENT', (
    tester,
  ) async {
    api.transport = PlaybackTransport.pinnedTls;

    await pumpPlayer(tester, server: _server(allowUnverifiedPlayback: true));
    host.emitPosition(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // Still there after playback has moved on: what was given up is ongoing,
    // so a dialog that could be dismissed would understate it.
    expect(find.textContaining('session cookie'), findsOneWidget);
    expect(find.textContaining('no certificate'), findsOneWidget);
  });

  testWidgets('D10 — no banner on a server that never enabled the override', (
    tester,
  ) async {
    // M4.R/T5: nothing asserted the banner's ABSENCE, so dropping the guard
    // entirely — a standing "the player checks no certificate" on every server
    // in the app — passed all 358 mobile tests. The default `plainHttp` and
    // not `pinnedTls`, because a pinned server with the flag off is REFUSED
    // and the refusal panel replaces the column the banner sits in: that arm
    // would pass for a reason that has nothing to do with the guard.
    await pumpPlayer(tester, server: _server());

    expect(host.opened, hasLength(1));
    expect(find.byType(UnverifiedTlsBanner), findsNothing);
  });

  testWidgets('D10 — no banner where mpv really does verify', (tester) async {
    // M4.R/P5: the banner was keyed on the SETTING. With the flag on and an
    // OS-trusted certificate `PlayerController` passes `verifyTls: true`, so
    // mpv verifies and the banner's own sentence was false.
    api.transport = PlaybackTransport.osTrustedTls;

    await pumpPlayer(tester, server: _server(allowUnverifiedPlayback: true));

    expect(host.opened.single.verifyTls, isTrue);
    expect(find.byType(UnverifiedTlsBanner), findsNothing);
  });

  testWidgets('D10 — a pinned server with no override refuses, naming why', (
    tester,
  ) async {
    api.transport = PlaybackTransport.pinnedTls;

    await pumpPlayer(tester);

    expect(find.textContaining('cannot check it'), findsOneWidget);
    expect(host.opened, isEmpty);
  });

  testWidgets('a dead session offers sign-in rather than a dead screen', (
    tester,
  ) async {
    api.playbackHeadersResult = SessionExpired(
      Uri.parse('http://nas.local/api/me'),
    );
    var signedIn = 0;

    await pumpPlayer(tester, onSignIn: () => signedIn++);
    await tester.tap(find.text('Sign in'));

    expect(signedIn, 1);
  });

  testWidgets('leaving the route reports a stop before it pops', (
    tester,
  ) async {
    await pumpPlayer(tester);
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 30))
      ..emitPosition(const Duration(seconds: 35));
    await tester.pumpAndSettle();

    // `maybePop` goes through `PopScope`, which is where the awaited final
    // report lives — the one that makes the pointer right when a user simply
    // walks out of the film.
    final state = tester.state<NavigatorState>(find.byType(Navigator));
    await state.maybePop();
    await tester.pumpAndSettle();

    expect(api.reports.last.event, ProgressEvent.stop);
  });

  testWidgets('the route pops WITH the outcome, read after the last report', (
    tester,
  ) async {
    // F9's second clause needs a value to travel on, and this is the route it
    // travels: `MediaDetailPage` applies it rather than re-fetching (M4.R/P3).
    // Read AFTER the awaited final `stop`, because that report is what moves
    // the pointer to where the user actually stopped.
    PlaybackOutcome? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                popped = await Navigator.of(context).push<PlaybackOutcome>(
                  MaterialPageRoute(
                    builder: (_) => PlayerPage(
                      api: api,
                      hostFactory: () => host,
                      nowPlayingFactory: fakeNowPlayingFactory(),
                      network: network,
                      detail: _detail(),
                      server: _server(),
                      prefs: const PlaybackPrefs(),
                      initialFile: const FileIndex(0),
                      startAt: Duration.zero,
                    ),
                  ),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 30));
    await tester.pumpAndSettle();

    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.state.pointer?.seconds, 30);
    expect(popped!.needsDetailRefetch, isFalse);
  });

  testWidgets('meets the tap-target and contrast guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPlayer(tester);
    host.emitDuration(const Duration(seconds: 100));
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('NF6 — the lifecycle listener is registered, not merely built', (
    tester,
  ) async {
    // A lazily-constructed `AppLifecycleListener` never registers with the
    // binding, so the pause report — the only thing that survives an OS kill —
    // would never fire. This drives the real binding rather than the
    // controller method.
    await pumpPlayer(tester);
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 20))
      ..emitPosition(const Duration(seconds: 25));
    await tester.pumpAndSettle();

    final pausesBefore = host.calls.where((c) => c == 'pause').length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();

    expect(api.reports.last.event, ProgressEvent.pause);
    // F14: the report is what the listener exists for, and the engine keeps
    // playing behind it.
    expect(host.calls.where((c) => c == 'pause'), hasLength(pausesBefore));
  });

  group('F14 — the lock-screen transport follows the screen', () {
    testWidgets('opening the player publishes what is playing', (tester) async {
      final session = FakeNowPlaying();
      addTearDown(session.dispose);

      await pumpPlayer(
        tester,
        nowPlayingFactory: fakeNowPlayingFactory(session),
      );
      await tester.pumpAndSettle();

      expect(session.published.single.title, 'Direct Play Movie');
    });

    testWidgets('leaving the player takes the session down', (tester) async {
      final session = FakeNowPlaying();
      addTearDown(session.dispose);

      await pumpPlayer(
        tester,
        nowPlayingFactory: fakeNowPlayingFactory(session),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // Two pumps: `dispose` fires the teardown unawaited so the frame is not
      // held, and the awaits inside it settle on the next microtask drain.
      await tester.pumpAndSettle();
      await tester.pump();

      expect(session.cleared, 1);
    });

    testWidgets('a session that arrives after the screen has gone is torn '
        'down rather than bound', (tester) async {
      // Starting the platform session is a round trip, and a user who backs
      // out during it would otherwise be left with a transport notification
      // driving a disposed controller. `_gone` is the guard; deleting it
      // leaves `cleared` at 0 and a live binder on a dead player.
      final session = FakeNowPlaying();
      addTearDown(session.dispose);
      final gate = Completer<NowPlayingHost>();

      await pumpPlayer(tester, nowPlayingFactory: () => gate.future);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      gate.complete(session);
      await tester.pumpAndSettle();

      expect(session.published, isEmpty);
      expect(session.cleared, 1);
    });
  });

  testWidgets('a rejected report says progress is no longer being saved', (
    tester,
  ) async {
    await pumpPlayer(tester);
    api.progressResult = BadRequest(
      Uri.parse('http://nas.local/p'),
      'bad file index',
    );
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 40));
    await tester.pumpAndSettle();

    // Non-blocking on purpose: playback carries on and only the pointer is
    // lost, so this is a line of text rather than a dialog.
    expect(find.textContaining('no longer being saved'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-surface')), findsOneWidget);
  });

  testWidgets('Not now leaves the metered prompt without playing', (
    tester,
  ) async {
    network.answer = NetworkType.metered;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => PlayerPage(
                  api: api,
                  hostFactory: () => host,
                  nowPlayingFactory: fakeNowPlayingFactory(),
                  network: network,
                  detail: _detail(size: 900 * 1000 * 1000),
                  server: _server(),
                  prefs: const PlaybackPrefs(),
                  initialFile: const FileIndex(0),
                  startAt: Duration.zero,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsNothing);
    expect(host.opened, isEmpty);
  });

  testWidgets('a server that stops answering cannot trap the user', (
    tester,
  ) async {
    await pumpPlayer(tester);
    host
      ..emitDuration(const Duration(seconds: 100))
      ..emitPosition(const Duration(seconds: 30))
      ..emitPosition(const Duration(seconds: 35));
    await tester.pumpAndSettle();
    // Long enough to outlast the two-second bound, short enough that the
    // pump below can drain it — a pending timer at teardown is an error.
    api.progressDelay = const Duration(seconds: 4);

    final state = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(state.maybePop());
    // The final report is bounded at two seconds. Past that the pop happens
    // anyway: a dead server must not be able to hold someone on the player.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerControls), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  group('formatPosition', () {
    test('minutes and seconds under an hour, hours past it', () {
      expect(formatPosition(Duration.zero), '0:00');
      expect(formatPosition(const Duration(seconds: 9)), '0:09');
      expect(formatPosition(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(formatPosition(const Duration(hours: 1, seconds: 5)), '1:00:05');
      expect(
        formatPosition(const Duration(hours: 2, minutes: 4, seconds: 5)),
        '2:04:05',
      );
      // Negative is not reachable from mpv, but a clamp beats a '-1:-1'.
      expect(formatPosition(const Duration(seconds: -5)), '0:00');
    });
  });
}
