part of 'errors.dart';

/// The server's certificate is not trusted and nothing is pinned (F15).
///
/// **The trust-on-first-use prompt, not a failure to report.** Self-signed and
/// private-CA certificates are the common case for a self-hosted server, so
/// this is the normal first connection to one. The UI shows [fingerprint] —
/// alongside [subject], [issuer] and [validTo], which are what let a user tell
/// "my own server" from "something else" — and if they accept it, the caller
/// writes the pin and rebuilds the client.
///
/// Nothing was sent. The refusal happens inside the TLS handshake, so the
/// server received no request at all and no cookie left the device.
final class CertificateNotTrusted extends FileFinApiException {
  /// [requested]'s certificate is untrusted and unpinned.
  const CertificateNotTrusted(
    this.requested, {
    required this.fingerprint,
    required this.subject,
    required this.issuer,
    required this.validTo,
  });

  /// The URL that was being requested.
  final Uri requested;

  /// The SHA-256 the user is being asked to compare, in colon-hex.
  final String fingerprint;

  /// The certificate's subject, e.g. `/CN=filefin.lan`.
  final String subject;

  /// The certificate's issuer; equal to [subject] for a self-signed one.
  final String issuer;

  /// When the certificate stops being valid.
  final DateTime validTo;

  @override
  String toString() =>
      'CertificateNotTrusted: ${redactUserInfo(requested)} presented an '
      'untrusted certificate ($subject, issued by $issuer, valid to '
      '${validTo.toIso8601String()}). SHA-256 $fingerprint';
}

/// A pinned server presented a **different** certificate (F15).
///
/// The loud, blocking half of F15, and the one that must never soften into a
/// prompt. `filefin_api` does not update the stored pin when this happens, and
/// no code path in this package can: a changed fingerprint on a pinned server
/// is the exact event pinning exists to make visible.
///
/// Nothing was sent — see `CertificatePinner.securityContext` for why that is
/// true even when the new certificate is one the OS would happily trust.
///
/// It also fires for an innocent cause: pinning a CA-signed server means every
/// certificate renewal changes the fingerprint. That is the price of the
/// guarantee, and the message names both values so a user can compare them.
final class CertificatePinMismatch extends FileFinApiException {
  /// [requested] presented [actual] where [expected] was pinned.
  const CertificatePinMismatch(
    this.requested, {
    required this.expected,
    required this.actual,
  });

  /// The URL that was being requested.
  final Uri requested;

  /// The fingerprint the user accepted earlier, in colon-hex.
  final String expected;

  /// The fingerprint that arrived this time, in colon-hex.
  final String actual;

  @override
  String toString() =>
      'CertificatePinMismatch: ${redactUserInfo(requested)} presented '
      '$actual, but $expected was pinned. Nothing was sent.';
}
