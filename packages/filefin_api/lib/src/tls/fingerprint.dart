import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// The SHA-256 of a certificate, in the form a human compares by eye.
///
/// **Lowercase colon-hex is a deliberate choice, not a formatting default.**
/// It is what `openssl x509 -fingerprint -sha256` prints and what every
/// browser's certificate viewer shows, so the string F15 puts on screen next
/// to "does this match your server?" is the same string the user is looking at
/// in the other window. A base64 digest, or a bare hex run, would be correct
/// and useless for the one job this value has.
///
/// The digest is over the certificate's **DER**, which is what
/// `X509Certificate.der` gives and what both tools above hash.
@immutable
final class CertificateFingerprint {
  const CertificateFingerprint._(this.value);

  /// The fingerprint of [certificate], computed the way openssl computes it.
  factory CertificateFingerprint.of(X509Certificate certificate) =>
      CertificateFingerprint.fromDer(certificate.der);

  /// The fingerprint of a DER-encoded certificate.
  factory CertificateFingerprint.fromDer(Uint8List der) =>
      CertificateFingerprint._(_join(sha256.convert(der).bytes));

  /// Reads a fingerprint a user typed, pasted, or we stored earlier.
  ///
  /// Case-insensitive and separator-insensitive: `:`, `-` and spaces are all
  /// dropped, because those are the three forms the tools people copy from
  /// produce. What is *not* tolerated is a wrong length or a non-hex
  /// character — a mistyped pin must fail loudly where the user can see it,
  /// rather than becoming a value that quietly matches nothing forever.
  factory CertificateFingerprint.parse(String text) {
    final cleaned = text.replaceAll(RegExp(r'[:\-\s]'), '').toLowerCase();
    if (cleaned.length != _digestHexLength || !_allHex.hasMatch(cleaned)) {
      throw ArgumentError.value(
        text,
        'text',
        'is not a SHA-256 certificate fingerprint: expected '
            '$_digestHexLength hex characters after removing ":", "-" and '
            'spaces, got ${cleaned.length}',
      );
    }
    return CertificateFingerprint._(
      _bytePair.allMatches(cleaned).map((m) => m[0]!).join(':'),
    );
  }

  /// The canonical lowercase colon-hex form.
  final String value;

  /// SHA-256 is 32 bytes, so 64 hex characters once separators are gone.
  static const _digestHexLength = 64;

  static final RegExp _allHex = RegExp(r'^[0-9a-f]+$');

  /// One byte of an already-validated hex run.
  ///
  /// Regrouping goes through this rather than through
  /// `for (var i = 0; i < n; i += 2)`, and the reason is the mutation gate. An
  /// indexed loop hands it an `i += 2` to rewrite as `i = 2`, which does not
  /// fail a test — it **hangs** one, and `mutation_test` reports a hang as an
  /// undetected mutant rather than a killed one (STATE.md records that it
  /// cannot tell the two apart). Measured here the hard way: that exact mutant
  /// ran the suite out of heap. This version has no index to get wrong.
  static final RegExp _bytePair = RegExp('[0-9a-f]{2}');

  static String _join(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');

  @override
  bool operator ==(Object other) =>
      other is CertificateFingerprint && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
