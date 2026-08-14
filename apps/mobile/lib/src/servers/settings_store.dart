import 'dart:convert';
import 'dart:io';

import 'package:filefin_mobile/src/servers/settings.dart';

/// Reads and writes `settings.json` in an **injected** directory.
///
/// The directory is a constructor argument rather than a
/// `getApplicationSupportDirectory()` call inside, which is the whole
/// testability story: a plugin call here would make every settings test stand
/// up a binding and a fake channel. `main()` makes it once and hands the
/// result in.
///
/// **Nothing secret is written here**: this is plain JSON any app on a
/// rooted device can read.
class SettingsStore {
  /// Stores `settings.json` under [directory].
  const SettingsStore(this.directory);

  /// Where the file lives. says the application support directory.
  final Directory directory;

  /// The file itself, exposed so a test can corrupt it deliberately.
  File get file => File('${directory.path}/settings.json');

  /// Reads the settings, or [AppSettings.empty] when there is nothing usable.
  ///
  /// **A corrupt file is empty settings, not a crash** rather than
  /// leniency: a file an older build wrote is something to replace, not to
  /// migrate. Starting over costs a user their server list; refusing to launch
  /// costs them the app.
  ///
  /// `Object` is caught rather than a list of types, deliberately here where it
  /// would be wrong almost anywhere else: four vocabularies (`FormatException`,
  /// `TypeError`, `CastError`, `FileSystemException`) answer one question — is
  /// this file usable — the same way.
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
  /// cannot read is answerable — start over with nothing. A file we
  /// cannot write has no answer: the server just added is gone at the next
  /// launch, with nothing on screen to look at.
  ///
  /// **Every call site catches [FileSystemException]** and says so through
  /// [describeSettingsWriteFailure]. One of them, `HomeRoute._switchTo`, is
  /// `unawaited(...)` with no `runZonedGuarded`, so its throw once went nowhere
  /// and the user was told nothing.
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
