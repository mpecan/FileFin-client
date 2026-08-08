import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/widgets.dart';

/// The three things the whole app is built on, constructed once in `main()`.
///
/// A plain object behind one `InheritedWidget` rather than a service locator:
/// a locator is global mutable state that a widget test has to reset between
/// cases, and forgetting to reset it makes one test's fake leak into the next.
@immutable
class AppDependencies {
  /// Holds the secret store, the settings store and the API factory.
  const AppDependencies({
    required this.secrets,
    required this.settings,
    required this.apiFactory,
  });

  /// Where the session, the password and the certificate pin live (§9).
  final SecretStore secrets;

  /// Where `settings.json` lives. Holds no secrets.
  final SettingsStore settings;

  /// Builds the API for one saved server.
  ///
  /// A factory rather than a single client because F11 is one client per
  /// `ServerId`, each with its own cookie jar, secret namespace and pin —
  /// sharing any of the three between servers is how one server's session
  /// cookie reaches another.
  final LibraryApi Function(SavedServer server) apiFactory;
}

/// Hands [AppDependencies] down the tree.
class FileFinScope extends InheritedWidget {
  /// Wraps [child] with [dependencies].
  const FileFinScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  /// What every screen reaches for.
  final AppDependencies dependencies;

  /// The dependencies above [context].
  ///
  /// It throws rather than returning null when there is no scope. A nullable
  /// return would push the same `!` to every call site, and a missing scope is
  /// a wiring mistake that should fail at the first widget that needs it with
  /// a sentence naming the cause.
  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FileFinScope>();
    if (scope == null) {
      throw StateError(
        'No FileFinScope above this widget. Every screen needs one; main() '
        'wraps the app in it and a widget test has to do the same.',
      );
    }
    return scope.dependencies;
  }

  @override
  bool updateShouldNotify(FileFinScope oldWidget) =>
      !identical(oldWidget.dependencies, dependencies);
}
