import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/now_playing.dart';
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
/// **`secrets` is here because the accept-and-pin loop reads it**, and not
/// before: removed the field precisely because nothing did. The pin
/// must be resolved into memory before a client is built.
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
    required this.nowPlayingFactory,
  });

  /// Where `settings.json` lives. Holds no secrets.
  final SettingsStore settings;

  /// Where the session, the password and the certificate pin live.
  ///
  /// Read to resolve a pin before a client is built, and written when a user
  /// accepts a certificate. Nothing else in `apps/mobile` may touch it: every
  /// other secret is `filefin_api`'s to write, which is what keeps the
  /// password out of this layer entirely.
  final SecretStore secrets;

  /// Builds the API for one saved server, at the certificate it was trusted
  /// with.
  ///
  /// A factory rather than a single client because there is one client per
  /// `ServerId`, each with its own cookie jar, secret namespace and pin —
  /// sharing any of the three between servers is how one server's session
  /// cookie reaches another.
  ///
  /// `pin` is the accepted fingerprint. `apiForServer` is what reads it out
  /// of [secrets] and hands it over; callers should use it rather than this
  /// directly, so the read happens in one place.
  final LibraryApi Function(SavedServer server, {CertificateFingerprint? pin})
  apiFactory;

  /// The connection sample, as a port so a widget test can set it.
  final NetworkStatus network;

  /// Builds a playback engine.
  ///
  /// **A factory, not an instance**, and for a sharper reason than the API
  /// one: an mpv context holds a position and a loaded file, so two player
  /// screens sharing one would fight over both. One host per screen, disposed
  /// with it.
  final PlaybackHost Function() playbackHostFactory;

  /// Opens the media session — the lock-screen transport and, on Android,
  /// the foreground service that stops the OS muting a backgrounded player.
  ///
  /// **A factory returning a FUTURE, and per PROCESS rather than per screen** —
  /// the opposite of [playbackHostFactory], for the opposite reason: there is
  /// one lock screen and `AudioService.init` asserts on a second call
  /// (`docs/field-notes.md`). `openNowPlaying` memoises.
  ///
  /// Deliberately not called from `main()`: nothing touches the media-session
  /// channel until a player screen opens, which is what keeps the cold start
  /// at the one plugin call it has always had.
  final Future<NowPlayingHost> Function() nowPlayingFactory;
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
