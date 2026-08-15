import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The trust store libmpv verifies against, because it will not find one.
///
/// The shipped players link mbedTLS on both platforms and have no system trust
/// store, so with no `tls-ca-file` they verify against no anchors at all and
/// refuse an ordinary public certificate. Two answers, in order of preference:
///
/// 1. **the device's own store**, exported through [channel]. Current, and it
///    holds enterprise roots a shipped file cannot. Only Android answers.
/// 2. **the roots shipped in the app**, written to [cacheDirectory]. iOS has
///    no API to enumerate system roots, so this is its only answer.
abstract final class CaBundle {
  /// The channel `MainActivity` answers `exportCaBundle` on.
  @visibleForTesting
  static const channel = MethodChannel('dev.filefin.filefin_mobile/ca_bundle');

  /// The bundled roots: Mozilla's, as distributed by curl.
  @visibleForTesting
  static const asset = 'assets/ca/cacert.pem';

  /// Where the shipped roots are written when the host has no store to export.
  ///
  /// Injected rather than resolved here, because resolving it means a second
  /// `path_provider` call and `main()` already holds a directory. It is also
  /// what lets every arm below run in an ordinary test.
  static Directory? cacheDirectory;

  /// The bundle the shipped roots are read from. Swapped in tests.
  @visibleForTesting
  static AssetBundle assets = rootBundle;

  static Future<String?>? _pending;
  static String? _path;

  /// A PEM file libmpv can be handed as `tls-ca-file`, or null if neither
  /// answer is available.
  static Future<String?> get path async {
    if (_path != null) return _path;
    return _pending ??= _resolve();
  }

  /// Forgets what was resolved, so each test starts from nothing.
  ///
  /// The cache is `static` because there is one trust store per process and
  /// re-resolving it on every open would write a file per playback. That makes
  /// it state a test has to be able to reset.
  @visibleForTesting
  static void reset() {
    _path = null;
    _pending = null;
  }

  static Future<String?> _resolve() async =>
      _path = await _exportFromHost() ?? await _writeShippedRoots();

  static Future<String?> _exportFromHost() async {
    String? exported;
    try {
      exported = await channel.invokeMethod<String>('exportCaBundle');
    } on MissingPluginException {
      return null;
    }
    // An empty string means the KeyStore was empty. Handing mpv a path to an
    // empty file is worse than handing it none: `tls-verify` would then trust
    // nothing at all, which is the failure this class exists to prevent.
    return (exported == null || exported.isEmpty) ? null : exported;
  }

  /// Materialises the shipped roots into a file, **overwriting** any previous
  /// copy.
  ///
  /// Rewritten on every cold start rather than written once: an app update
  /// ships a new bundle, and a cached copy from the previous version would
  /// keep a revoked root alive and hide a newly added one for as long as the
  /// install lasts.
  static Future<String?> _writeShippedRoots() async {
    final dir = cacheDirectory;
    if (dir == null) return null;
    try {
      final pem = await assets.loadString(asset);
      if (pem.isEmpty) return null;
      final file = File('${dir.path}/cacert.pem');
      await file.parent.create(recursive: true);
      await file.writeAsString(pem, flush: true);
      return file.path;
    } on Exception {
      // A trust store we cannot write is not a reason to fail the launch. The
      // caller leaves `tls-ca-file` unset, and playback refuses on its own
      // terms rather than crashing here.
      return null;
    }
  }
}
