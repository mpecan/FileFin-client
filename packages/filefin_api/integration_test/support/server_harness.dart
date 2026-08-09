import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filefin_core/filefin_core.dart';

import 'fixture_run.dart';

/// A real `filefin` process over a private copy of the seeded library.
///
/// **Server control is Dart, not shell**, because the restart happens *in the
/// middle of a test*: `session_recovery_test.dart` logs in, browses, kills the
/// server, starts it again and asserts the caller never noticed. A shell
/// wrapper can start a server before a suite and stop one after; it cannot do
/// that.
class FileFinTestServer {
  FileFinTestServer._(this.run, this._log);

  /// This server's private run directory.
  final FixtureRun run;

  final File _log;

  Process? _process;

  /// The base URL a client should be pointed at.
  Uri get baseUrl => run.baseUrl;

  /// Copies the seeded library and starts a server over it.
  ///
  /// [transcoding] is the server's own `transcodeEnabled` setting, written
  /// into this copy's config — see [FixtureRun.create].
  static Future<FileFinTestServer> start({bool transcoding = true}) async {
    final run = await FixtureRun.create(transcoding: transcoding);
    final server = FileFinTestServer._(
      run,
      File('${run.root.path}/server.log'),
    );
    await server._spawn();
    return server;
  }

  /// Stops the server and waits for the process to actually be gone.
  ///
  /// **Awaiting `exitCode` is what makes a restart possible.** Sending SIGTERM
  /// and returning immediately races the old listener: the new process tries
  /// to bind the same port and dies with "address already in use", and the
  /// failure surfaces one test later as a connection refused with no cause.
  /// SIGKILL after five seconds so a wedged server cannot hang the suite
  /// instead.
  Future<void> stop() async {
    final process = _process;
    if (process == null) return;
    _process = null;
    // SIGTERM is `kill`'s default, so the analyzer calls the argument
    // redundant. It stays: which signal this sends is the difference between a
    // clean shutdown and a corrupted SQLite cache, and a reader must not have
    // to look a default up to know which one happens.
    // ignore: avoid_redundant_argument_values
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }

  /// Stops and starts again on the same port — every session is now gone.
  ///
  /// This is L1 reproduced deliberately: sessions live in the server's memory
  /// (`auth.go`, `sessionStore`) and do not survive the process.
  Future<void> restart() async {
    await stop();
    await _spawn();
  }

  /// Deletes the run directory. Call after [stop].
  Future<void> dispose() => run.dispose();

  /// The last [lines] of the server's own output.
  ///
  /// Printed on failure by every suite, because otherwise every integration
  /// failure reads "connection refused" and says nothing about why.
  String logTail([int lines = 40]) {
    if (!_log.existsSync()) return '(no server log)';
    final all = _log.readAsLinesSync();
    return all.skip(all.length - lines < 0 ? 0 : all.length - lines).join('\n');
  }

  Future<void> _spawn() async {
    final process = await Process.start(
      FixtureRun.binary.path,
      ['serve'],
      environment: run.environment,
      workingDirectory: run.root.path,
    );
    _process = process;
    // Both streams append to the same file, written synchronously and flushed.
    // An `IOSink` would be tidier and is wrong twice over: a sink can only be
    // bound to one stream at a time (`addStream` on the second throws "already
    // bound"), and its buffering means `logTail` — the thing that explains a
    // failure — could read an empty file at exactly the moment it matters.
    process.stdout.listen(_append);
    process.stderr.listen(_append);
    await _awaitReady();
  }

  /// Polls `GET /api/state` until it answers like FileFin, or fails loudly.
  ///
  /// **Readiness is not "any 200".** The SPA catch-all answers `200 text/html`
  /// for anything (`server.go:352`), and a partially-initialised server can
  /// answer one too — so a poll that accepted a status would return before the
  /// API existed and the first real request would fail for a reason nobody
  /// could reconstruct. The bar is `200` **and** `application/json` **and** a
  /// `version` field: the same three facts F1 uses, for the same reason.
  ///
  /// It **throws** on the deadline. It never returns "not ready" for a caller
  /// to ignore.
  Future<void> _awaitReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    final client = HttpClient();
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (await _answersLikeFileFin(client)) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } finally {
      client.close(force: true);
    }
    throw StateError(
      'the filefin server at $baseUrl did not become ready within 10s.\n'
      'Last 40 lines of its log:\n${logTail()}',
    );
  }

  void _append(List<int> bytes) =>
      _log.writeAsBytesSync(bytes, mode: FileMode.append, flush: true);

  Future<bool> _answersLikeFileFin(HttpClient client) async {
    try {
      final request = await client.getUrl(
        baseUrl.replace(path: FileFinUrls(baseUrl).state.path),
      );
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        return false;
      }
      final type = response.headers.contentType?.mimeType;
      final body = await utf8.decoder.bind(response).join();
      if (type != 'application/json') return false;
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> &&
          decoded.containsKey('version') &&
          decoded.containsKey('needsSetup');
    } on Object {
      // Connection refused while it is still starting is the normal case, not
      // an error worth reporting — the deadline above is what turns a server
      // that never starts into a failure.
      return false;
    }
  }
}
