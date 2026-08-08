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
  void write(AppSettings settings) {
    directory.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(settings.toJson()));
  }
}
