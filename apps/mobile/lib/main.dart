import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/audio_service_now_playing.dart';
import 'package:filefin_mobile/src/playback/media_kit_playback_host.dart';
import 'package:filefin_mobile/src/playback/mpv_player.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/platform_secret_store.dart';
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
/// **One `SecretStore` for the process, and from M7.2 it persists.** F3 needs
/// the password in memory for the process lifetime — a re-auth cannot await a
/// Keychain prompt in the middle of a 401 retry — so [PlatformSecretStore] is a
/// persistence decorator around the in-memory cache rather than a replacement
/// for it, and reads still come from memory once anything has been read once.
///
/// The second plugin call in this package lives behind it. It is not made here
/// and it is not made at launch: nothing touches the Keychain until something
/// asks for a secret, which is why `main()` still has exactly one plugin call
/// on its own critical path (NF1).
/// It is called by [main] above, in this same file, and by `main_test.dart`.
/// `main.dart` has no `part`, so it is its own library and the check reports
/// it for the same reason it reports the seven below — this is the same
/// class, not one of its own (§5, `public_member_no_consumer`).
@visibleForTesting
Widget buildApp(Directory support, {required FormFactor formFactor}) {
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
      // `pin` is F15's accepted fingerprint, resolved by `apiForServer` before
      // this is called: TLS's callbacks are synchronous and cannot await a
      // store read, so a client is built for one pin and a NEW one is built
      // when that pin changes. Until M7.5 nothing passed it and every shipped
      // client ran `CertificatePinner(pin: null)`.
      apiFactory: (server, {pin}) => FileFinLibraryApi(
        FileFinClient.forServer(
          server: server.id,
          baseUrl: server.baseUrl,
          secrets: secrets,
          pin: pin,
          username: server.lastUser.isEmpty ? null : server.lastUser,
        ),
      ),
    ),
    child: FileFinApp(formFactor: formFactor),
  );
}
