/// The payloads captured from a real FileFin server (§8), as raw **text**.
///
/// `filefin_core` has a sibling helper that decodes them into maps. This one
/// deliberately does not: what `filefin_api` needs is the exact bytes a real
/// server sent, so the stub can hand them straight back over a socket and the
/// decoding under test is this package's own. Decoding here first would prove
/// the fixture parses, which is `filefin_core`'s job and already covered.
library;

import 'dart:io';

/// `test/fixtures/` relative to a package root.
///
/// `filefin_core`'s version walks up looking for the `justfile`. This one does
/// not, on purpose: both `dart test` and `mutation_test` run from the package
/// root, so the relative path holds, and a near-copy of that walk would be a
/// 15-line clone for `just dupes` to object to. The guard below is what turns
/// a wrong working directory into one clear sentence instead of a
/// `FileSystemException` about a path nobody recognises.
const fixtureDir = '../../test/fixtures';

/// The raw bytes of `test/fixtures/<name>`, as text.
String fixtureText(String name) => _fixture(name).readAsStringSync();

/// The raw bytes of `test/fixtures/<name>`, undecoded.
///
/// `poster.jpg` is the only binary fixture, and reading it as text would be
/// lossy in a way that hides the very thing it asserts: the poster route
/// serves the seeded file through `http.ServeFile`, so what is being checked
/// is that the bytes arrive unchanged.
List<int> fixtureBytes(String name) => _fixture(name).readAsBytesSync();

File _fixture(String name) {
  final file = File('$fixtureDir/$name');
  if (!file.existsSync()) {
    throw StateError(
      'no fixture at ${file.absolute.path}. This helper assumes the current '
      'directory is the package root, which is where `dart test` and '
      'mutation_test both run from.',
    );
  }
  return file;
}
