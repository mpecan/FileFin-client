import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/main.dart' as entrypoint;
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/playback/media_kit_playback_host.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('filefin-main-');
    PathProviderPlatform.instance = _FakePathProvider(dir);
    addTearDown(() => dir.deleteSync(recursive: true));
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
      '"baseUrl":"http://nas.local","lastUser":"sam","wifiOnly":false,'
      '"allowUnverifiedPlayback":false}],'
      '"playback":{"progressIntervalSecs":30,"meteredWarnBytes":500000000}}',
    );

    await entrypoint.main();
    await tester.pump();

    expect(find.text('Signed out'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the dependencies it builds are usable', (tester) async {
    await tester.pumpWidget(entrypoint.buildApp(dir));
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
    final app = entrypoint.buildApp(dir) as FileFinScope;

    expect(app.dependencies.network, isA<ConnectivityNetworkStatus>());
    // The factory is INVOKED, not merely inspected: what is being pinned is
    // that it builds a real `MediaKitPlaybackHost` over a real `RealMpvPlayer`.
    // On a machine where libmpv resolves through media_kit's platform default
    // names that returns a host; on macOS the default list is
    // `Mpv.framework/Mpv` and nothing else (measured, M4.0/E2b), so it throws
    // instead — and the throw names the framework, which is the same evidence.
    try {
      final host = app.dependencies.playbackHostFactory();
      expect(host, isA<MediaKitPlaybackHost>());
      await host.dispose();
    } on Object catch (e) {
      expect('$e', contains('Mpv'));
    }
  });
}
