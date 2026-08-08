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

/// Starts a server, registers teardown, and prints its log if the test fails.
///
/// `addTearDown` immediately after the start, in one helper, so a suite cannot
/// leak a server by throwing between the two — a leaked server holds a port and
/// the next failure reads "address already in use" with no hint about who.
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
