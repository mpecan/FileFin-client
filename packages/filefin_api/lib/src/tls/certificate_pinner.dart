import 'dart:io';

import 'package:filefin_api/src/tls/fingerprint.dart';
import 'package:filefin_api/src/tls/pin_decision.dart';

/// Holds one server's pin and answers both of TLS's synchronous questions.
///
/// **The pin is resolved into memory before the client is built, and that is
/// forced by the platform.** `badCertificateCallback` and `validateCertificate`
/// are `bool`-returning and synchronous: neither can await a secret-store read
/// or a user prompt. So accepting an unknown certificate is a **separate,
/// caller-driven act** — the request fails with `CertificateNotTrusted`
/// carrying the observed fingerprint, the UI asks the user, the caller writes
/// the pin and rebuilds the client. This class never writes a pin, and a
/// mismatch never updates one.
///
/// It records the last certificate seen per `host:port`, because by the time
/// dio surfaces the failure the synchronous callback is long gone and the
/// exception carries only a `HandshakeException`. Without this the error could
/// say "TLS failed" and nothing more, which is precisely the message F15 exists
/// to replace.
class CertificatePinner {
  /// Pins [pin], or trusts the OS when it is null.
  CertificatePinner({this.pin});

  /// The fingerprint the user accepted earlier, or null for OS trust.
  final CertificateFingerprint? pin;

  final Map<String, _Seen> _seen = {};

  /// The `SecurityContext` an `HttpClient` for this pinner must use.
  ///
  /// **`withTrustedRoots: false` whenever a pin exists, and this is the
  /// difference between blocking and merely complaining.** Measured against
  /// dio 5.11.0 and dart:io:
  ///
  /// - `badCertificateCallback` runs *during the handshake*. Returning false
  ///   raises `HandshakeException` and the server records **zero requests** —
  ///   nothing was sent, so no session cookie left the device.
  /// - `validateCertificate` runs *after the response headers arrive*.
  ///   Returning false does reject, but the server had already logged the
  ///   request. A design resting on it alone would hand the request — cookie
  ///   included — to a server whose certificate had changed, and only then
  ///   object.
  ///
  /// dart:io calls `badCertificateCallback` only for a chain the context does
  /// not trust. So with the default context an OS-trusted certificate never
  /// reaches it, and a pinned server that later gets a real CA certificate
  /// would change fingerprint with the callback never firing — the silent
  /// re-accept F15 forbids. Trusting no roots when pinned routes every
  /// certificate through the handshake-time hook and closes that hole *before*
  /// bytes are sent.
  ///
  /// Without a pin the default context is used — `HttpClient` treats a null
  /// context as `SecurityContext.defaultContext` — so ordinary public HTTPS
  /// keeps working exactly as the OS says it should.
  ///
  SecurityContext? get securityContext {
    if (pin == null) return null;
    // `withTrustedRoots: false` is SecurityContext's own default, so the
    // analyzer calls it redundant. It stays written out: this argument IS the
    // mechanism, a reader must see what the line does without looking a
    // default up, and an upstream default that flipped would turn pinning off
    // in silence.
    // ignore: avoid_redundant_argument_values
    return SecurityContext(withTrustedRoots: false);
  }

  /// `HttpClient.badCertificateCallback` — asked during the handshake.
  ///
  /// Per *connection*, not per request: a pooled connection is established
  /// once and reused, so this alone would not re-check anything.
  bool allowBadCertificate(
    X509Certificate certificate,
    String host,
    int port,
  ) => _judge(certificate, host, port, trustedByOs: false) is AcceptCertificate;

  /// `IOHttpClientAdapter.validateCertificate` — asked per response.
  ///
  /// The per-request half [allowBadCertificate] cannot provide. It sees the
  /// leaf certificate of whichever connection actually served this response,
  /// pooled or fresh, and it is also the hook that runs on a plain-`http://`
  /// response — where [certificate] is null and there is nothing to judge.
  bool validate(X509Certificate? certificate, String host, int port) =>
      certificate == null ||
      _judge(certificate, host, port, trustedByOs: true) is AcceptCertificate;

  /// The last decision made for [url]'s host and port, if any.
  PinDecision? decisionFor(Uri url) =>
      _seen[_key(url.host, url.port)]?.decision;

  /// The last certificate seen for [url]'s host and port, if any.
  X509Certificate? certificateFor(Uri url) =>
      _seen[_key(url.host, url.port)]?.certificate;

  PinDecision _judge(
    X509Certificate certificate,
    String host,
    int port, {
    required bool trustedByOs,
  }) {
    final decision = decidePin(
      pinned: pin,
      observed: CertificateFingerprint.of(certificate),
      trustedByOs: trustedByOs,
    );
    _seen[_key(host, port)] = _Seen(certificate, decision);
    return decision;
  }

  static String _key(String host, int port) => '$host:$port';

  @override
  String toString() =>
      'CertificatePinner(${pin == null ? 'unpinned' : 'pinned $pin'})';
}

class _Seen {
  const _Seen(this.certificate, this.decision);

  final X509Certificate certificate;
  final PinDecision decision;
}
