import 'dart:io' show Platform;

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
class CaBundle {
  CaBundle._();

  static const _channel = MethodChannel('dev.filefin.filefin_mobile/ca_bundle');

  static Future<String?>? _pending;
  static String? _path;

  /// The exported PEM file path, or null when unavailable or still loading.
  ///
  /// Returns null on non-Android platforms and when the export fails.
  /// Callers that guarded with `Platform.isAndroid` can treat null as "not
  /// yet ready" and retry; everywhere else null means "not needed."
  static Future<String?> get path async {
    if (!Platform.isAndroid) return null;
    if (_path != null) return _path;
    return _pending ??= _export();
  }

  static Future<String?> _export() async {
    try {
      _path = await _channel.invokeMethod<String>('exportCaBundle');
    } on MissingPluginException {
      _path = null;
    }
    // An empty string means the KeyStore was empty — treat as unavailable.
    if (_path != null && _path!.isEmpty) _path = null;
    return _path;
  }
}
