import 'dart:convert';
import 'dart:io';

import 'package:filefin_mobile/src/servers/settings.dart';

/// Reads and writes `settings.json` in an **injected** directory.
///
/// The directory is a constructor argument rather than a
/// `getApplicationSupportDirectory()` call inside, and that is the whole
/// testability story: a plugin call here would make every settings test need a
/// Flutter binding and a fake platform channel, mocking the one layer that
/// matters. `main()` makes the plugin call once and hands the result in;
/// `main_test.dart` covers that single line through
/// `PathProviderPlatform.instance`, which is a supported seam.
///
/// **Nothing secret is written here** (§9). This is plain JSON any app on a
/// rooted device can read; the session, the password and the certificate pin
/// live in `SecretStore`.
class SettingsStore {
  /// Stores `settings.json` under [directory].
  const SettingsStore(this.directory);

  /// Where the file lives. SPEC.md §7 says the application support directory.
  final Directory directory;

  /// The file itself, exposed so a test can corrupt it deliberately.
  File get file => File('${directory.path}/settings.json');

  /// Reads the settings, or [AppSettings.empty] when there is nothing usable.
  ///
  /// **A corrupt file is empty settings, not a crash**, and the reasoning is
  /// §13's rather than leniency: our own format changes freely before release,
  /// so a file an older build wrote is not something to migrate — it is
  /// something to replace. Starting over costs a user their server list;
  /// refusing to launch costs them the app.
  ///
  /// `Object` is caught rather than a list of types, and that is deliberate
  /// here where it would be wrong almost anywhere else. The failure modes are a
  /// `FormatException` from `jsonDecode`, a `TypeError` from a wrong shape, a
  /// `CastError` from a wrong element type and a `FileSystemException` from a
  /// permissions problem — four vocabularies for one question, "is this file
  /// usable", whose answer is the same for all of them.
  AppSettings read() {
    try {
      if (!file.existsSync()) return AppSettings.empty;
      final decoded = jsonDecode(file.readAsStringSync());
      return AppSettings.fromJson(decoded! as Map<String, Object?>);
      // The four failure vocabularies above are one question with one answer,
      // and listing them would leave the fifth one nobody thought of crashing
      // a launch. The lint is right everywhere except here.
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      return AppSettings.empty;
    }
  }

  /// Writes the settings, creating the directory if it is not there.
  ///
  /// **This one throws, and the asymmetry with [read] is the point.** A file we
  /// cannot read is answerable — start over with nothing (§13). A file we
  /// cannot write has no answer at all: the server the user just added is gone
  /// at the next launch, and there is nothing on screen to look at.
  ///
  /// **All five call sites catch [FileSystemException] and say so through
  /// [describeSettingsWriteFailure].** This used to read "the two screens that
  /// call this", and by M7.4 it was three screens and two methods on
  /// `HomeRoute` — one of which, `_switchTo`, is invoked `unawaited(...)` with
  /// no `runZonedGuarded` anywhere, so its throw went nowhere at all and the
  /// user was told nothing. A comment that counts its callers is a comment
  /// that decays; this one names the rule instead.
  void write(AppSettings settings) {
    directory.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(settings.toJson()));
  }
}

/// What a user is told when `settings.json` could not be written.
///
/// The OS message is included rather than swallowed. "Could not save" gives a
/// user nothing to act on; "Permission denied" and "No space left on device"
/// are different problems with different fixes, and this app cannot tell which
/// it is any better than the OS already has.
String describeSettingsWriteFailure(FileSystemException error) =>
    'This app could not save its settings file '
    '(${error.osError?.message ?? error.message}). Nothing was written, so '
    'this will not be here after a restart.';
