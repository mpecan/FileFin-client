import 'dart:convert';
import 'dart:io';

/// A private copy of the seeded FileFin run directory, for one suite.
///
/// **Seed once, copy per suite.** Seeding is three ffmpeg encodes and a cache
/// rebuild — ten seconds and more — while copying the 4.2 MB result and
/// rewriting two fields takes milliseconds. A suite that reseeded would be slow
/// enough to skip, and a suite people skip is worse than no suite.
///
/// Three facts about how `filefin` finds its state drove this, all verified
/// against upstream at v0.20.3. Get any of them wrong and the harness fails in
/// a way that looks like a client bug:
///
/// 1. **`--port` is IGNORED once a config exists.** `bootstrapServe`
///    (`cmd/filefin/main.go:85`) returns early when `config.Exists()` and only
///    *warns* about a differing `--port`. The port comes from the config file,
///    so the copy's `port` must be rewritten — passing a flag instead would
///    silently collide every suite on 8099.
/// 2. **The config is `$HOME/.filefin.json`** (`internal/config/config.go:201`)
///    and its `dataDir` is **absolute**, so it has to be repointed at the copy.
/// 3. **The SQLite cache lives under `os.UserCacheDir()`**
///    (`internal/db/db.go:18`), not in the data dir — `$HOME/Library/Caches` on
///    macOS, `$XDG_CACHE_HOME` or `$HOME/.cache` on Linux. Copying the whole
///    seeded `home/` carries it wherever the seed put it, and `cache.db-wal`
///    and `cache.db-shm` come along with it: SQLite runs in WAL mode, so a copy
///    without the `-wal` file loses committed rows and the library comes back
///    empty.
/// The account `tool/testserver/seed.sh` installs, as `meta.json` keys it.
const seededUser = 'testuser';

class FixtureRun {
  FixtureRun._(this.root, this.port);

  /// The temporary directory holding this suite's `home/` and `data/`.
  final Directory root;

  /// The port written into this copy's config.
  final int port;

  /// The seeded run directory every copy is made from.
  static Directory get seeded => Directory(
    Platform.environment['FILEFIN_RUN'] ??
        '${Platform.environment['HOME']}/development/filefin-test/run',
  );

  /// The `filefin` binary under test.
  static File get binary => File(
    Platform.environment['FILEFIN_BIN'] ??
        '${Platform.environment['HOME']}/development/filefin-test/filefin',
  );

  /// Copies the seeded run directory and rewrites the config for this suite.
  static Future<FixtureRun> create() async {
    if (!Directory('${seeded.path}/data').existsSync()) {
      throw StateError(
        'no seeded run directory at ${seeded.path}. `just it` seeds one; '
        'running a suite directly needs tool/testserver/seed.sh first.',
      );
    }
    final root = await Directory.systemTemp.createTemp('filefin-it-');
    await _copyInto(seeded, root);
    final port = await freePort();
    final config = File('${root.path}/home/.filefin.json');
    final json =
        jsonDecode(await config.readAsString()) as Map<String, Object?>;
    json['port'] = port;
    json['dataDir'] = '${root.path}/data';
    json['bindAddress'] = '127.0.0.1';
    await config.writeAsString(jsonEncode(json));
    await _repointCache(root, from: '${seeded.path}/data');
    await _decorrelateWatched(root);
    return FixtureRun._(root, port);
  }

  /// Points the copied SQLite cache at the copied media.
  ///
  /// **Without this the copy is not isolated at all, and the divergence is
  /// silent.** `media.path` and `media_files.path` are stored ABSOLUTE, so a
  /// copied cache still addresses the shared seed. Two consequences, both
  /// measured against v0.20.3:
  ///
  /// 1. every suite read media bytes — and computed `size` — from the seed, so
  ///    a suite that ever mutated a file would corrupt every other suite;
  /// 2. `relTo(dataDir, f.Path)` returns the path **unchanged** when the row is
  ///    not under `dataDir`, so `files[].path` came back as
  ///    `/Users/…/filefin-test/run/data/Shows/…mkv` where the committed fixture
  ///    and `docs/server-api.md` both say "relative to the data dir". An M3
  ///    playback milestone that trusted `path` would have been testing a shape
  ///    the real world never sends.
  ///
  /// The rows are rewritten rather than the cache dropped, because the cache
  /// also holds `users` and `user_state` — dropping it would delete the account
  /// every suite logs in as. `sqlite3` does the edit because the alternative is
  /// a native SQLite dependency in a package that has no other use for one
  /// (§4); `run-integration.sh` refuses when it is missing, the way it refuses
  /// a missing `ffmpeg`.
  ///
  /// It **verifies**, and that is not ceremony: an upstream schema change that
  /// moved these columns would otherwise leave the harness silently doing
  /// nothing and the absolute paths back.
  static Future<void> _repointCache(
    Directory root, {
    required String from,
  }) async {
    final db = _cacheDatabase(root);
    final to = '${root.path}/data';
    const tables = ['media', 'media_files'];
    final sql = StringBuffer();
    for (final table in tables) {
      sql.writeln(
        "UPDATE $table SET path = replace(path, '${_q(from)}', '${_q(to)}') "
        "WHERE path LIKE '${_q(from)}%';",
      );
    }
    sql.writeln('PRAGMA wal_checkpoint(TRUNCATE);');
    for (final table in tables) {
      sql.writeln(
        "SELECT '$table', sum(path LIKE '${_q(from)}%'), "
        "sum(path LIKE '${_q(to)}/%') FROM $table;",
      );
    }
    final result = await Process.run('sqlite3', [db.path, '$sql']);
    if (result.exitCode != 0) {
      throw StateError(
        'could not repoint ${db.path} at $to: ${result.stderr}\n'
        'Is `sqlite3` on PATH? `just it` checks for it; a suite run directly '
        'does not.',
      );
    }
    // `wal_checkpoint` prints a row of its own, so the report lines are picked
    // out by their table name rather than by position.
    final reported = {
      for (final line in '${result.stdout}'.trim().split('\n'))
        if (tables.contains(line.split('|').first)) line.split('|').first: line,
    };
    for (final table in tables) {
      final parts = reported[table]?.split('|');
      if (parts == null || parts[1] != '0' || parts[2] == '0') {
        throw StateError(
          'repointing the cache left $table wrong (${reported[table]}). The '
          'columns holding absolute media paths have moved; find them with '
          '`sqlite3 <cache.db> .schema` and update this list.',
        );
      }
    }
  }

  /// The copied cache, wherever `os.UserCacheDir()` put it for this platform.
  ///
  /// Searched rather than hard-coded: Go picks `$HOME/Library/Caches` on macOS
  /// and `$XDG_CACHE_HOME`/`$HOME/.cache` on Linux, and a harness that knew
  /// only one of them would fail on the other machine with "no media" rather
  /// than with a sentence.
  static File _cacheDatabase(Directory root) {
    final home = Directory('${root.path}/home');
    final found = home
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('/cache.db'));
    if (found.isEmpty) {
      throw StateError('no cache.db under ${home.path} — the seed is stale');
    }
    return found.first;
  }

  /// SQL single-quote escaping, for the two paths interpolated above.
  static String _q(String value) => value.replaceAll("'", "''");

  /// Makes `watched` the OPPOSITE of `transcode`, in every copy, on every
  /// machine.
  ///
  /// **The two were perfectly correlated in the seeded library, so the one
  /// assertion the whole playback design turns on proved nothing.** The show is
  /// HEVC (`transcode: true`) and `tool/testserver/capture_fixtures.sh` marks it
  /// watched; the film is H.264 and is not. So `transcode: json['watched']`
  /// decoded every live payload correctly and all nineteen integration tests
  /// stayed green — in the test whose own comment calls this "the one thing the
  /// whole playback design turns on (SPEC.md §3.4)". Marking the DIRECT-PLAY
  /// item watched and the transcoding one unwatched makes that substitution
  /// wrong in both directions at once.
  ///
  /// It also makes the suite **reproducible**. `run-integration.sh` seeds only
  /// when `$RUN/data` is missing, so whether a machine's library carried this
  /// per-user state depended on whether fixtures had ever been captured there —
  /// two machines, two different libraries, one of them silently blind. State
  /// the copy needs is written by the copy.
  ///
  /// Per-user state lives in the item's own `meta.json` under `state.<user>`
  /// (`importer.go`); the cache's `user_state` table is a projection the server
  /// rebuilds from it, so this is the one place worth writing.
  ///
  /// **The whole `state.<user>` block is REPLACED, not merged**, and that is
  /// the second half of the reproducibility argument above rather than a
  /// tidy-up. An earlier version preserved `progress` "because a later
  /// milestone will want it", and the effect was that `just it` stopped being
  /// idempotent with respect to `just fixtures-capture`:
  /// `tool/testserver/capture_fixtures.sh` POSTs favourite, rating, watched
  /// **and progress** against the shared seed, and those land permanently in
  /// `meta.json`. Measured at M4.R — seed with `state: null` → 12/12 green;
  /// run `just fixtures-capture` → the show gains `progress {file: "1x2"}` →
  /// **10 pass, 2 fail on unmodified code**, because
  /// `playback_test.dart` asserts absolute literals (`continueSeconds == 1`,
  /// `continueIndex == 0`) that hold only when the pointer is unset. Exactly
  /// the failure this method's own comment describes for `watched`, left open
  /// for everything else. A copy that starts from a state it wrote itself is
  /// the only kind that answers the same on two machines.
  static Future<void> _decorrelateWatched(Directory root) async {
    final metas = Directory('${root.path}/data')
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('/meta.json'));
    for (final meta in metas) {
      final json = jsonDecode(meta.readAsStringSync()) as Map<String, Object?>;
      json['state'] = <String, Object?>{
        seededUser: <String, Object?>{
          'watched': meta.path.contains('/Films/'),
          'updated': 1,
        },
      };
      meta.writeAsStringSync(jsonEncode(json));
    }
  }

  /// The base URL a client should be pointed at.
  Uri get baseUrl => Uri.parse('http://127.0.0.1:$port');

  /// The environment the child server must run under.
  ///
  /// `HOME` is what makes it read the copied config, and `XDG_CACHE_HOME` is
  /// set explicitly so a Linux run lands inside the copy too. On macOS Go's
  /// `UserCacheDir` ignores it and follows `HOME`, so setting it there is
  /// harmless — one map that is correct on both platforms beats two that are
  /// each correct on one.
  Map<String, String> get environment => {
    'HOME': '${root.path}/home',
    'XDG_CACHE_HOME': '${root.path}/home/.cache',
  };

  /// Deletes the copy.
  Future<void> dispose() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }

  /// An ephemeral loopback port, bound and released.
  ///
  /// Bind-and-close rather than a fixed number: `-j 1` keeps suites sequential
  /// today, but a fixed port is a collision waiting for the day it does not.
  static Future<int> freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  static Future<void> _copyInto(Directory from, Directory to) async {
    await for (final entity in from.list(recursive: true, followLinks: false)) {
      final relative = entity.path.substring(from.path.length + 1);
      final target = '${to.path}/$relative';
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await Directory(
          target.substring(0, target.lastIndexOf('/')),
        ).create(recursive: true);
        await entity.copy(target);
      }
    }
  }
}
