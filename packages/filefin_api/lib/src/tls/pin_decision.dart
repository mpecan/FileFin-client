import 'package:filefin_api/src/tls/fingerprint.dart';

/// What to do about one certificate (F15).
sealed class PinDecision {
  /// Allows the variants below to be `const`.
  const PinDecision();
}

/// Proceed with the connection.
final class AcceptCertificate extends PinDecision {
  /// The certificate is either pinned, OS-trusted, or absent entirely.
  const AcceptCertificate();
}

/// Refuse: nothing is pinned and the OS does not trust this certificate.
///
/// **This is the trust-on-first-use prompt, not an error to swallow.** The
/// caller shows [observed] to the user, and if they accept it, writes it to
/// the secret store and rebuilds the client. `filefin_api` never writes a pin
/// itself — accepting a certificate is a decision a person makes, and code
/// that could make it on their behalf is code that eventually does.
final class RejectUntrusted extends PinDecision {
  /// The untrusted certificate had fingerprint [observed].
  const RejectUntrusted(this.observed);

  /// What the connection actually presented.
  final CertificateFingerprint observed;
}

/// Refuse: a pin exists and this certificate is not it.
///
/// The loud, blocking half of F15. It never updates the stored pin — a
/// changed fingerprint on a pinned server is exactly the event pinning exists
/// to make visible, and silently re-accepting it would be the "silent
/// re-accept" F15 forbids, implemented by us.
final class RejectChanged extends PinDecision {
  /// [expected] was pinned; [actual] arrived instead.
  const RejectChanged({required this.expected, required this.actual});

  /// The fingerprint the user accepted earlier.
  final CertificateFingerprint expected;

  /// The fingerprint that arrived this time.
  final CertificateFingerprint actual;
}

/// The whole of F15's policy, as one pure total function.
///
/// Everything routes through here — both TLS hooks, both call sites — because
/// this is the only part of certificate pinning that can be *proven* without a
/// device: it takes three values and returns one, so all twelve combinations
/// are table-tested. What cannot be proven on this machine is the wiring of
/// the OS-trusted arm, which needs a CA-signed certificate for `127.0.0.1`.
/// Keeping the policy pure is what confines that gap to wiring.
///
/// The order of the rules is the argument:
///
/// 1. **No certificate means no TLS.** dio calls `validateCertificate` on
///    every response including a plain-`http://` one, where the certificate is
///    null — measured against dio 5.11.0. F15 permits plain http for LAN
///    servers, so rejecting a null certificate would break every plain-http
///    request the moment a pin was stored for some *other* server.
/// 2. **A pin outranks OS trust, in both directions.** A pinned server whose
///    certificate changes is refused even when the new one is perfectly valid;
///    that is the point. A pinned self-signed certificate is accepted even
///    though no OS trusts it; that is also the point. The consequence worth
///    knowing: pinning a CA-signed server means its renewals need re-accepting.
/// 3. **With no pin, OS trust decides**, and a failure is a prompt rather than
///    an error — see [RejectUntrusted].
///
/// [trustedByOs] is not guessed at either call site. `badCertificateCallback`
/// passes `false`, because dart:io calls it precisely when the chain did not
/// validate — and when a pin exists the client is built with
/// `withTrustedRoots: false` so *every* certificate arrives there.
/// `validateCertificate` passes `true`, because it runs only after a handshake
/// that already succeeded under whatever rules applied.
PinDecision decidePin({
  required CertificateFingerprint? pinned,
  required CertificateFingerprint? observed,
  required bool trustedByOs,
}) {
  if (observed == null) return const AcceptCertificate();
  if (pinned != null) {
    return pinned == observed
        ? const AcceptCertificate()
        : RejectChanged(expected: pinned, actual: observed);
  }
  return trustedByOs ? const AcceptCertificate() : RejectUntrusted(observed);
}
