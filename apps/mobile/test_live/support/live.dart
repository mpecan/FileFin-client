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
import '../../../../packages/filefin_api/integration_test/support/fixture_run.dart';
import '../../../../packages/filefin_api/integration_test/support/server_harness.dart';

export '../../../../packages/filefin_api/integration_test/support/server_harness.dart'
    show FileFinTestServer;

/// The account `tool/testserver/seed.sh` installs.
const seededCredentials = Credentials(
  username: 'testuser',
  password: 'TestPassw0rd!23',
);

/// The **second** account `FixtureRun` writes into every copy, so a two-server
/// suite can sign in with credentials that genuinely differ (F11, M7.0/E-3).
const secondCredentials = Credentials(
  username: secondUser,
  password: secondPassword,
);

/// Starts a real `filefin` over a private copy of the seeded library and
/// returns an API signed in to it.
///
/// [transcoding] is the server's own `transcodeEnabled` setting, written into
/// this copy's config (`FixtureRun.create`). `false` is what gives F12's 415 a
/// real server behind it.
///
/// Every caller must be in a **real** async zone — `setUpAll`, `setUp` or a
/// plain `test()`. A request initiated inside a `testWidgets` body registers
/// its timers in that body's `FakeAsync` zone and never completes, whatever
/// `runAsync` does afterwards (measured at M3.0, re-learned at M3.7).
Future<LibraryApi> liveApi({bool transcoding = true}) async {
  final api = liveApiFor(
    await liveServer(transcoding: transcoding),
    InMemorySecretStore(),
  );
  await api.login(seededCredentials);
  return api;
}

/// A real `filefin` over a private copy of the seeded library, torn down with
/// the test, and **still running** when this returns.
///
/// Separate from [liveApi] because two things M7 needs cannot be expressed
/// against a signed-in API alone: restarting the server mid-test (L1, and the
/// cold start F3 renews), and pointing a *second* client at the same server.
Future<FileFinTestServer> liveServer({bool transcoding = true}) async {
  final server = await FileFinTestServer.start(transcoding: transcoding);
  addTearDown(() async {
    await server.stop();
    await server.dispose();
  });
  return server;
}

/// A `LibraryApi` for [server], namespaced under [id] in [secrets].
///
/// **Both arguments are the point.** Building a second client over the *same*
/// store and the *same* id is what an app restart looks like from
/// `filefin_api`'s side — nothing else in the process survives it — and
/// building two clients over the same store under *different* ids is F11.
///
/// [username] is what `main.dart` passes out of `settings.json`'s `lastUser`,
/// and it is **not optional in production**: `SessionManager._renew` reads the
/// username from memory, so a client built without one cannot renew silently
/// however good the stored password is. `cold_start_live_test.dart` pins both
/// arms.
LibraryApi liveApiFor(
  FileFinTestServer server,
  SecretStore secrets, {
  ServerId id = const ServerId('live'),
  String? username,
}) {
  final api = FileFinLibraryApi(
    FileFinClient.forServer(
      server: id,
      baseUrl: server.baseUrl,
      secrets: secrets,
      username: username,
    ),
  );
  addTearDown(api.close);
  return api;
}
