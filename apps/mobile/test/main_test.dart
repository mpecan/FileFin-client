import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/main.dart' as entrypoint;
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/playback/media_kit_playback_host.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/shell/form_factor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/libmpv.dart';

/// Covering `main()`'s single plugin call, through the plugin's own seam.
///
/// `PathProviderPlatform.instance` is how `path_provider` is meant to be
/// substituted — it is not a `MethodChannel` handler faked from underneath. The
/// alternative is that `getApplicationSupportDirectory()` is an uncoverable
/// line, and `MAX_UNCOVERED=0` would have to rise for exactly one line of
/// wiring.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.directory);

  final Directory directory;

  @override
  Future<String?> getApplicationSupportPath() async => directory.path;
}

void main() {
  setUpAll(() {
    ensureLibmpv();
    useHeadlessPlayer();
  });

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-main-');
    PathProviderPlatform.instance = _FakePathProvider(dir);
    // The SECOND plugin `main()` now depends on, and the same kind of seam.
    // Without it `PlatformSecretStore`'s first read throws
    // `MissingPluginException` (measured, M7.0/E-4) out of F2's cold start,
    // which is neither a `FileFinApiException` nor anything a launch can do
    // about.
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() => dir.deleteSync(recursive: true));

    // `main()` now asks the host whether it is a television before it calls
    // `runApp`. Answered here rather than left unhandled: an un-mocked channel
    // completes off the `FakeAsync` clock this body runs on, and the `await`
    // below then never returns — measured as a ten-minute timeout rather than
    // a failure, which is the worst shape a test can have.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(formFactorChannel, (_) async => false);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(formFactorChannel, null),
    );
  });

  testWidgets('main() resolves the support directory and starts the app', (
    tester,
  ) async {
    await entrypoint.main();
    await tester.pump();

    expect(find.byType(FileFinApp), findsOneWidget);
    expect(find.text('No server yet'), findsOneWidget);
  });

  testWidgets('the tree it builds reads settings from THAT directory', (
    tester,
  ) async {
    // The assertion that the injected directory is actually used: a build that
    // ignored it would still show the empty state, so a "renders" test alone
    // proves nothing about the wiring.
    File('${dir.path}/settings.json').writeAsStringSync(
      '{"servers":[{"id":"a","name":"Attic NAS", '
      '"baseUrl":"http://nas.local","lastUser":"sam","authMode":"password",'
      '"wifiOnly":false,"allowUnverifiedPlayback":false}],'
      '"playback":{"progressIntervalSecs":30,"meteredWarnBytes":500000000},'
      // M7.3's key. Without it the strict decoder discards the whole file
      // (§13) and this test would assert "No server yet" while believing it
      // had proved the directory was read.
      '"selectedServerId":null}',
    );

    await entrypoint.main();
    await tester.pump();
    // The second frame: a saved server means F2's cold start runs, and only
    // once its `restore()` has failed does the signed-out screen appear.
    await tester.pump();

    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the dependencies it builds are usable', (tester) async {
    await tester.pumpWidget(
      entrypoint.buildApp(dir, formFactor: FormFactor.phone),
    );
    await tester.pump();

    final deps = tester
        .widget<FileFinScope>(find.byType(FileFinScope))
        .dependencies;

    expect(deps.settings.directory.path, dir.path);
    // The factory really builds a client for the server it is handed, rather
    // than one shared client — F11 is one cookie jar, one secret namespace and
    // one certificate pin PER server.
    final api = deps.apiFactory(
      SavedServer(
        id: const ServerId('x'),
        name: 'x',
        baseUrl: Uri.parse('http://nas.local'),
      ),
    );
    addTearDown(api.close);
    expect(api.server.value, 'x');
  });
  testWidgets('main() wires the REAL playback engine, not a stub', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('filefin-main-play-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final app =
        entrypoint.buildApp(dir, formFactor: FormFactor.phone) as FileFinScope;

    expect(app.dependencies.network, isA<ConnectivityNetworkStatus>());
    // The factory is INVOKED, not merely inspected: what is pinned is that it
    // builds a real `MediaKitPlaybackHost` over a real `RealMpvPlayer`.
    //
    // **Inside `runAsync`, and headless, and BOTH are load-bearing.** A real
    // `Player` built under a widget test's fake clock parks work on timers
    // that fake time never advances, and one built without `vo=null`/`ao=null`
    // opens output devices; `dispose()` then waits for either and never
    // returns. Not a failure — a ten-minute timeout that reports as a hung
    // suite, which is the shape CLAUDE.md warns a gate must never take.
    // Each condition alone still hangs; the pair was measured together.
    await tester.runAsync(() async {
      final host = app.dependencies.playbackHostFactory();
      expect(host, isA<MediaKitPlaybackHost>());
      await host.dispose();
    });
  });
}
