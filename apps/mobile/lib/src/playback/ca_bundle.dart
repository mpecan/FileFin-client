import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The device's live CA trust store, exported as a PEM file for mpv.
///
/// Android's system trust store is not a PEM bundle — it is individual DER
/// files, and inside the Conscrypt APEX on API 34+. libmpv reads neither, so
/// every `tls-verify=yes` connection fails with "Failed to open".
///
/// [path] exports the device's real trust store through a platform channel and
/// returns a file `tls-ca-file` can be handed, regenerated on every cold start
/// so new enterprise CAs are picked up. iOS and desktop need no bundle.
///
/// `abstract final` rather than a private constructor, which would be a line
/// nothing could ever run.
abstract final class CaBundle {
  /// The channel `MainActivity` answers `exportCaBundle` on.
  ///
  @visibleForTesting
  static const channel = MethodChannel('dev.filefin.filefin_mobile/ca_bundle');

  static Future<String?>? _pending;
  static String? _path;

  /// The exported PEM file path, or null when unavailable or still loading.
  ///
  /// Returns null on any host with no handler for the channel — iOS, desktop
  /// and the test runner — and when the export fails.
  ///
  /// **No `Platform.isAndroid` guard, and its removal is the point.** The guard
  /// made every line below unreachable under `flutter test`, which reports
  /// macOS, so the export and its error arms were shipped untested. It bought
  /// nothing either: a host with no handler answers `MissingPluginException`,
  /// which is what iOS and desktop do and what [_export] already catches.
  static Future<String?> get path async {
    if (_path != null) return _path;
    return _pending ??= _export();
  }

  /// Forgets what was exported, so each test starts from nothing.
  ///
  /// The cache is `static` because there is one trust store per process and
  /// re-exporting it on every open would write a file per playback. That makes
  /// it state a test has to be able to reset.
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
