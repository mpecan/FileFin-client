import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/audio_service_now_playing.dart';
import 'package:filefin_mobile/src/playback/ca_bundle.dart';
import 'package:filefin_mobile/src/playback/media_kit_playback_host.dart';
import 'package:filefin_mobile/src/playback/mpv_player.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/platform_secret_store.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:filefin_mobile/src/shell/form_factor.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

/// Builds the app's dependencies and starts it.
///
/// **The only plugin call in this package is the one below**, and everything
/// downstream of it takes an injected `Directory` instead. That is what lets
/// `SettingsStore` be exercised with real `dart:io` file I/O in an ordinary
/// test rather than through a faked platform channel. `main_test.dart` covers
/// this line by replacing `PathProviderPlatform.instance`, which is the
/// plugin's own supported seam.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  runApp(buildApp(support, formFactor: await detectFormFactor()));
}

/// The widget tree, given the directory `settings.json` lives in.
///
/// Separate from [main] so a test can build the same tree over a temp
/// directory without touching the plugin at all.
///
/// **One `SecretStore` for the process**, memory-first for the reason
/// [PlatformSecretStore] gives. The second plugin call in this package lives
/// behind it and is not made at launch: nothing touches the Keychain until
/// something asks for a secret, which is why `main()` still has exactly one
/// plugin call on its critical path.
@visibleForTesting
Widget buildApp(Directory support, {required FormFactor formFactor}) {
  // Where the shipped CA roots are written when the host exports no store of
  // its own, which is every platform but Android. Injected from the directory
  // already resolved above rather than resolving a second one.
  CaBundle.cacheDirectory = support;
  final secrets = PlatformSecretStore();
  return FileFinScope(
    dependencies: AppDependencies(
      settings: SettingsStore(support),
      secrets: secrets,
      network: ConnectivityNetworkStatus(),
      // A NEW engine per player screen. libmpv holds a position and a loaded
      // file, so two screens sharing one context would fight over both.
      playbackHostFactory: () => MediaKitPlaybackHost(RealMpvPlayer()),
      nowPlayingFactory: openNowPlaying,
      // `pin` is the accepted fingerprint, resolved by `apiForServer` before
      // this is called: TLS's callbacks are synchronous and cannot await a
      // store read, so a client is built for one pin and a NEW one is built
      // when that pin changes. Until nothing passed it and every shipped
      // client ran `CertificatePinner(pin: null)`.
      apiFactory: (server, {pin}) => FileFinLibraryApi(
        switch (server.authMode) {
          AuthMode.password => FileFinClient.forServer(
            server: server.id,
            baseUrl: server.baseUrl,
            secrets: secrets,
            pin: pin,
            username: server.lastUser.isEmpty ? null : server.lastUser,
          ),
          AuthMode.token => FileFinClient.forTokenServer(
            server: server.id,
            baseUrl: server.baseUrl,
            secrets: secrets,
            pin: pin,
          ),
        },
      ),
    ),
    child: FileFinApp(formFactor: formFactor),
  );
}
