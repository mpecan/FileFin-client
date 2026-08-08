import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter_test/flutter_test.dart';

// Relative imports into `filefin_api`'s integration harness, deliberately.
//
// `server_harness.dart` and `fixture_run.dart` import only dart:io, dart:async,
// dart:convert and `package:filefin_core` — no `package:test` — so they load
// cleanly under `flutter_test`. `harness.dart` next to them does NOT: it
// imports `package:test`, and `package:test` and `flutter_test` cannot coexist
// in one suite. Hence the ten lines below rather than reusing it.
//
// The alternative — copying the harness — would be two server implementations
// drifting apart, and `just dupes` would be right to object.
import '../../../../packages/filefin_api/integration_test/support/server_harness.dart';

/// The account `tool/testserver/seed.sh` installs.
const seededCredentials = Credentials(
  username: 'testuser',
  password: 'TestPassw0rd!23',
);

/// Starts a real `filefin` over a private copy of the seeded library and
/// returns an API signed in to it.
///
/// Every caller must be in a **real** async zone — `setUpAll`, `setUp` or a
/// plain `test()`. A request initiated inside a `testWidgets` body registers
/// its timers in that body's `FakeAsync` zone and never completes, whatever
/// `runAsync` does afterwards (measured at M3.0, re-learned at M3.7).
Future<LibraryApi> liveApi() async {
  final server = await FileFinTestServer.start();
  final api = FileFinLibraryApi(
    FileFinClient.forServer(
      server: const ServerId('live'),
      baseUrl: server.baseUrl,
      secrets: InMemorySecretStore(),
    ),
  );
  addTearDown(() async {
    api.close();
    await server.stop();
    await server.dispose();
  });
  await api.login(seededCredentials);
  return api;
}
