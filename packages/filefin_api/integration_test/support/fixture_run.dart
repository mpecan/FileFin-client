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
    return FixtureRun._(root, port);
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
