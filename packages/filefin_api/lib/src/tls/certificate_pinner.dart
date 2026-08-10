import 'dart:io';

import 'package:filefin_api/src/tls/fingerprint.dart';
import 'package:filefin_api/src/tls/pin_decision.dart';
import 'package:meta/meta.dart';

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

  /// The `SecurityContext` [connect] hands to the handshake.
  ///
  /// **`withTrustedRoots: false` whenever a pin exists**, and it is what makes
  /// [connect]'s `trustedByOs` say the right thing. A pin outranks OS trust in
  /// both directions (`decidePin`, rule 2), so once one exists the platform's
  /// opinion is not an input to the decision — and a context that still trusted
  /// the OS roots would report `trustedByOs: true` for a certificate the pin is
  /// about to refuse, which reads as agreement where there is none.
  ///
  /// Without a pin the default context is used — a null context means
  /// `SecurityContext.defaultContext` — so `trustedByOs` is genuinely the
  /// platform's verdict and ordinary public HTTPS keeps working exactly as the
  /// OS says it should.
  ///
  /// It is deliberately **not** the mechanism that blocks. It used to be: with
  /// no trusted roots every chain fails verification, so every certificate
  /// reached `badCertificateCallback` — and that hook is handed the
  /// certificate where verification failed, which for a real chain is the CA.
  /// See [connect].
  /// Public only so a test can reach it; nothing outside this library calls
  /// it (§5, `public_member_no_consumer`).
  @visibleForTesting
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

  /// `HttpClient.connectionFactory` — establishes the socket, pin first.
  ///
  /// **This exists because `badCertificateCallback` is handed the wrong
  /// certificate.** dart:io calls that hook with the certificate at which chain
  /// verification *failed*, which for a multi-certificate chain is the CA at
  /// the top and not the leaf the server actually presented. Under
  /// `withTrustedRoots: false` every chain fails at the top, so a private-CA
  /// deployment — a reverse proxy, F15's stated common case — reached the hook
  /// with the CA. Measured at M2 against a `[leaf, ca]` chain: the
  /// trust-on-first-use prompt named the CA, pinning the value that prompt
  /// offered accepted **any** certificate that CA had ever issued, and pinning
  /// the server's real certificate was refused. A self-signed chain is one
  /// certificate long, so leaf and root are the same object and the whole
  /// defect is invisible — which is why the fixtures now include a real chain.
  ///
  /// Owning the connection is what fixes it. `SecureSocket.startConnect`
  /// completes the handshake and hands back a socket whose `peerCertificate`
  /// **is** the leaf, and dart:io has not written a request byte yet. So the
  /// pin is compared against the right certificate, and a refusal `destroy()`s
  /// the socket before the request — cookie included — exists on the wire.
  ///
  /// `onBadCertificate` returning `true` is not a relaxation: it defers the
  /// verdict to us rather than granting one. What it *is* is the only way to
  /// learn the OS's opinion, which is the third input `decidePin` needs — the
  /// callback fires exactly when the platform would have refused.
  ///
  /// The proxy arguments are unused because nothing in this package sets
  /// `HttpClient.findProxy`, so dart:io only ever calls this for a direct
  /// connection (`http_impl.dart`, `_ConnectionTarget.connect`). A proxied
  /// https connection would tunnel through `createProxyTunnel`, which secures
  /// the socket itself and would need its own gate; writing one now would be a
  /// branch nothing can reach (§1, §5).
  Future<ConnectionTask<Socket>> connect(Uri url, String? _, int? _) async {
    if (!url.isScheme('https')) return Socket.startConnect(url.host, url.port);
    var trustedByOs = true;
    final task = await SecureSocket.startConnect(
      url.host,
      url.port,
      context: securityContext,
      onBadCertificate: (_) {
        trustedByOs = false;
        return true;
      },
    );
    final socket = await task.socket;
    final decision = _judge(
      socket.peerCertificate,
      url.host,
      url.port,
      trustedByOs: trustedByOs,
    );
    if (decision is AcceptCertificate) return task;
    socket.destroy();
    // Host and port rather than the URL: a saved-server URL can carry
    // `user:password@` (§9), and this string travels inside a `DioException`
    // whose own `toString` prints it.
    throw HandshakeException(
      '${url.host}:${url.port} presented a certificate this client refused',
    );
  }

  /// `IOHttpClientAdapter.validateCertificate` — asked per response.
  ///
  /// The per-response half [connect] cannot provide: a pooled connection is
  /// established once and every later request rides it without a handshake, so
  /// only this hook re-checks them. It is also the hook that runs on a
  /// plain-`http://` response, where [certificate] is null — which
  /// `decidePin`'s first rule already answers, so there is no second policy
  /// here to disagree with the first.
  bool validate(X509Certificate? certificate, String host, int port) =>
      _judge(certificate, host, port, trustedByOs: true) is AcceptCertificate;

  /// The last decision made for [url]'s host and port, if any.
  PinDecision? decisionFor(Uri url) =>
      _seen[_key(url.host, url.port)]?.decision;

  /// The last certificate seen for [url]'s host and port, if any.
  X509Certificate? certificateFor(Uri url) =>
      _seen[_key(url.host, url.port)]?.certificate;

  PinDecision _judge(
    X509Certificate? certificate,
    String host,
    int port, {
    required bool trustedByOs,
  }) {
    final decision = decidePin(
      pinned: pin,
      observed: certificate == null
          ? null
          : CertificateFingerprint.of(certificate),
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

  final X509Certificate? certificate;
  final PinDecision decision;
}
