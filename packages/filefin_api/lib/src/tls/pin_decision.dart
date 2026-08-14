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
/// this is the only part of pinning provable without a device: three values in,
/// one out, so all twelve combinations are table-tested.
///
/// The rules in order, and the order is the argument (D19): **no certificate
/// means no TLS**, so a null one is accepted rather than breaking the
/// plain-http LAN servers F15 permits; **a pin outranks OS trust both ways**,
/// which is why a pinned CA-signed server needs re-accepting on renewal;
/// **with no pin, OS trust decides**, and a failure is a prompt rather than an
/// error ([RejectUntrusted]). [trustedByOs] is derived, never guessed.
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
