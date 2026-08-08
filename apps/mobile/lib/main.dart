import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/app.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
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
  runApp(buildApp(support));
}

/// The widget tree, given the directory `settings.json` lives in.
///
/// Separate from [main] so a test can build the same tree over a temp
/// directory without touching the plugin at all.
///
/// **One `SecretStore` for the process.** F3 needs the password in memory for
/// the process lifetime whatever the persistence story is — a re-auth cannot
/// await a Keychain prompt in the middle of a 401 retry — and M7's platform
/// store is a persistence decorator around exactly this object. The
/// consequence, stated out loud because silence would imply otherwise: nothing
/// persists a password at M3, so it is re-typed on every cold start.
Widget buildApp(Directory support) {
  final secrets = InMemorySecretStore();
  return FileFinScope(
    dependencies: AppDependencies(
      settings: SettingsStore(support),
      apiFactory: (server) => FileFinLibraryApi(
        FileFinClient.forServer(
          server: server.id,
          baseUrl: server.baseUrl,
          secrets: secrets,
          username: server.lastUser.isEmpty ? null : server.lastUser,
        ),
      ),
    ),
    child: const FileFinApp(),
  );
}
