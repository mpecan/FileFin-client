import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/widgets.dart';

/// The two things the whole app is built on, constructed once in `main()`.
///
/// A plain object behind one `InheritedWidget` rather than a service locator:
/// a locator is global mutable state that a widget test has to reset between
/// cases, and forgetting to reset it makes one test's fake leak into the next.
///
/// **`secrets` was deliberately absent until M7.5, and its return is a §5
/// story rather than a reversal.** M3 removed it because nothing read it:
/// `main()` built the `SecretStore` and closed over it in [apiFactory], so the
/// field was written once and read never. F15's accept-and-pin loop is what
/// finally reads it — the pin has to be resolved into memory *before* a client
/// is built, because TLS's callbacks are synchronous and cannot await a store
/// read — and accepting a certificate is what writes one.
@immutable
class AppDependencies {
  /// Holds the settings store, the secret store, the API factory and
  /// playback's two ports.
  const AppDependencies({
    required this.settings,
    required this.secrets,
    required this.apiFactory,
    required this.network,
    required this.playbackHostFactory,
  });

  /// Where `settings.json` lives. Holds no secrets.
  final SettingsStore settings;

  /// Where the session, the password and F15's pin live (§9).
  ///
  /// Read to resolve a pin before a client is built, and written when a user
  /// accepts a certificate. Nothing else in `apps/mobile` may touch it: every
  /// other secret is `filefin_api`'s to write, which is what keeps the
  /// password out of this layer entirely.
  final SecretStore secrets;

  /// Builds the API for one saved server, at the certificate it was trusted
  /// with.
  ///
  /// A factory rather than a single client because F11 is one client per
  /// `ServerId`, each with its own cookie jar, secret namespace and pin —
  /// sharing any of the three between servers is how one server's session
  /// cookie reaches another.
  ///
  /// `pin` is F15's accepted fingerprint. `apiForServer` is what reads it out
  /// of [secrets] and hands it over; callers should use it rather than this
  /// directly, so the read happens in one place.
  final LibraryApi Function(SavedServer server, {CertificateFingerprint? pin})
  apiFactory;

  /// F13's connection sample, as a port so a widget test can set it.
  final NetworkStatus network;

  /// Builds a playback engine.
  ///
  /// **A factory, not an instance**, and for a sharper reason than the API
  /// one: an mpv context holds a position and a loaded file, so two player
  /// screens sharing one would fight over both. One host per screen, disposed
  /// with it.
  final PlaybackHost Function() playbackHostFactory;
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
