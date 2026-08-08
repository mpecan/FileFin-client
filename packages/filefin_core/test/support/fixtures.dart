/// Reads the payloads captured from a real FileFin server (CLAUDE.md §8).
///
/// `dart:io` is deliberate and confined to `test/`: the purity gate
/// (`core_purity` in `tool/check-constitution.sh`) scans `lib/` only, because a
/// test reading a committed fixture is not the core reaching for the outside
/// world — it is the fixture arriving.
///
/// A hand-written JSON literal that agrees with our own class proves only that
/// we can spell our own field names, which is why every model test decodes one
/// of these instead.
library;

import 'dart:convert';
import 'dart:io';

/// The directory holding the `justfile`, found by walking up from the current
/// directory. `dart test` and `mutation_test` both run from the package root,
/// which is two levels below it.
Directory repoRoot() {
  var dir = Directory.current.absolute;
  while (!File('${dir.path}/justfile').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('no justfile above ${Directory.current.path}');
    }
    dir = parent;
  }
  return dir;
}

/// The raw bytes of `test/fixtures/<name>`, as text.
String fixtureText(String name) =>
    File('${repoRoot().path}/test/fixtures/$name').readAsStringSync();

/// `test/fixtures/<name>.json` decoded as a JSON object.
Map<String, Object?> loadFixture(String name) =>
    jsonDecode(fixtureText('$name.json')) as Map<String, Object?>;

/// `test/fixtures/<name>.json` decoded as a JSON array of objects.
List<Map<String, Object?>> loadFixtureList(String name) =>
    (jsonDecode(fixtureText('$name.json')) as List<Object?>)
        .cast<Map<String, Object?>>();
