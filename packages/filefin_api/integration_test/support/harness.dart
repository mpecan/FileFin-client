import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'server_harness.dart';

export 'fixture_run.dart';
export 'server_harness.dart';

/// The account `tool/testserver/seed.sh` installs.
const seededCredentials = Credentials(
  username: 'testuser',
  password: 'TestPassw0rd!23',
);

/// The saved-server id every suite uses.
const seededServer = ServerId('integration');

/// Asks `GET /api/me` with [session] through a client the code under test does
/// not own, and returns the status.
///
/// **The only channel that can tell "the server ended the session" from "this
/// app forgot it".** `SessionManager.logout` clears the jar and both secrets in
/// a `finally`, so every assertion made through `FileFinClient` passes whether
/// or not the server was ever asked — which is exactly how a `postUri` that
/// became a `getUri` stayed invisible to 791 tests. A bare `HttpClient` shares
/// no jar, no interceptor and no retry with the client, so nothing it reports
/// can be repaired on the way out.
Future<int> meStatusWithCookie(Uri base, String session) async {
  final http = HttpClient();
  try {
    final request = await http.getUrl(FileFinUrls(base).me);
    request.headers.add(
      HttpHeaders.cookieHeader,
      '$sessionCookieName=$session',
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    http.close(force: true);
  }
}

/// Starts a server, registers teardown, and prints its log if the test fails.
///
/// `addTearDown` immediately after the start, in one helper, so a suite cannot
/// leak a server by throwing between the two.
///
/// The teardown is right for a reason its own comment used to get wrong: it
/// claimed "a leaked server holds a port and the next failure reads address
/// already in use". That is **false** for this harness — `FixtureRun` binds
/// port 0 and the OS does not re-hand a port that is still LISTENing, and `just
/// it` was measured passing twice with five orphaned servers alive. What a leak
/// actually costs is a `filefin serve` process and a ~4 MB temp directory per
/// run, unbounded; `tool/run-integration.sh` reaps both before it starts,
/// because `addTearDown` does not run when the isolate is killed.
///
/// The log tail is what turns "connection refused" into a diagnosis, so it is
/// printed by the harness rather than left to each suite to remember.
Future<FileFinTestServer> startServer() async {
  final server = await FileFinTestServer.start();
  addTearDown(() async {
    // `printOnFailure` buffers and prints only when the test fails, which is
    // exactly the policy wanted: silent on a green run, and the server's own
    // words on a red one.
    printOnFailure('--- filefin server log ---\n${server.logTail()}');
    await server.stop();
    await server.dispose();
  });
  return server;
}
