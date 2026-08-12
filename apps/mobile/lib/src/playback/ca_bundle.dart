import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The device's live CA trust store, exported as a PEM file for mpv.
///
/// Android's system trust store is not a single PEM bundle — it lives as
/// individual DER files under `/system/etc/security/cacerts` (and inside the
/// Conscrypt APEX on API 34+). libmpv cannot read either, so every
/// `tls-verify=yes` connection fails with "Failed to open" — even for a valid
/// Let's Encrypt certificate.
///
/// The [path] getter calls through a platform channel to `AndroidCAStore` on
/// side, which reads every system and user-installed CA certificate, encodes
/// each as PEM, concatenates them, writes the result to the app's cache
/// directory, and returns the absolute path. From that point on,
/// `tls-ca-file` can be handed to mpv and `tls-verify=yes` works against the
/// device's actual trust store rather than a bundled snapshot.
///
/// Regenerated on every cold start so newly installed enterprise CAs are
/// picked up. On iOS and desktop the system libmpv uses the OS trust store
/// natively and no bundle is needed.
///
/// `abstract final` rather than a private constructor: the constructor was
/// there to stop the class being instantiated and was itself a line nothing
/// could ever run, which is the shape §1 asks to be deleted. The modifier says
/// the same thing to the compiler and to a reader, and costs no line.
abstract final class CaBundle {
  /// The channel `MainActivity` answers `exportCaBundle` on.
  ///
  /// Public so its own suite can mock it; nothing outside this library invokes
  /// it (§5, `public_member_no_consumer`).
  @visibleForTesting
  static const channel = MethodChannel('dev.filefin.filefin_mobile/ca_bundle');

  static Future<String?>? _pending;
  static String? _path;

  /// The exported PEM file path, or null when unavailable or still loading.
  ///
  /// Returns null on any host with no handler for the channel — iOS, desktop
  /// and the test runner — and when the export fails.
  /// Callers that guarded with `Platform.isAndroid` can treat null as "not
  /// yet ready" and retry; everywhere else null means "not needed."
  /// **No `Platform.isAndroid` guard, and its removal is the point.** The
  /// guard made every line below unreachable under `flutter test`, which
  /// reports macOS — so the export, its `MissingPluginException` arm and the
  /// empty-string rule were shipped and never once executed by a test. It also
  /// bought nothing: a host with no handler for this channel answers
  /// `MissingPluginException`, which is exactly what iOS and desktop do and
  /// exactly what [_export] already catches. Same reasoning as
  /// `shell/form_factor.dart`.
  static Future<String?> get path async {
    if (_path != null) return _path;
    return _pending ??= _export();
  }

  /// Forgets what was exported, so each test starts from nothing.
  ///
  /// The cache is `static` because there is one trust store per process and
  /// re-exporting it on every open would write a file per playback. That makes
  /// it state a test has to be able to reset (§3).
  @visibleForTesting
  static void reset() {
    _path = null;
    _pending = null;
  }

  static Future<String?> _export() async {
    try {
      _path = await channel.invokeMethod<String>('exportCaBundle');
    } on MissingPluginException {
      _path = null;
    }
    // An empty string means the KeyStore was empty — treat as unavailable.
    if (_path != null && _path!.isEmpty) _path = null;
    return _path;
  }
}
