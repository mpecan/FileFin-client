import 'package:filefin_api/filefin_api.dart';
import 'package:test/test.dart';

/// Two fingerprints that are definitely not each other.
final a = CertificateFingerprint.parse('aa' * 32);
final b = CertificateFingerprint.parse('bb' * 32);

void main() {
  group('CertificateFingerprint', () {
    test('parses the format openssl and every browser print', () {
      // Lowercase colon-hex is not a stylistic choice: it is what
      // `openssl x509 -fingerprint -sha256` and every browser certificate
      // viewer show, so what the user compares by eye is what we store.
      expect(
        CertificateFingerprint.parse(
          'CA:D8:55:4B:04:42:4A:95:C0:FF:95:96:66:7E:BB:87:'
          '8D:A9:54:50:97:99:02:A1:30:9D:09:E3:4D:8B:5A:11',
        ).value,
        'ca:d8:55:4b:04:42:4a:95:c0:ff:95:96:66:7e:bb:87:'
        '8d:a9:54:50:97:99:02:a1:30:9d:09:e3:4d:8b:5a:11',
      );
    });

    test('accepts the separatorless and spaced forms people paste', () {
      final canonical = CertificateFingerprint.parse('ab' * 32).value;
      expect(CertificateFingerprint.parse('AB' * 32).value, canonical);
      expect(
        CertificateFingerprint.parse(List.filled(32, 'ab').join(' ')).value,
        canonical,
      );
      expect(
        CertificateFingerprint.parse(List.filled(32, 'AB').join(':')).value,
        canonical,
      );
      // The hyphen form is what Windows' certificate export and a few CLIs
      // produce. It is in the strip set, and the mutation gate found nothing
      // asserting it — one character of that character class could be changed
      // with the whole suite still green.
      expect(
        CertificateFingerprint.parse(List.filled(32, 'ab').join('-')).value,
        canonical,
      );
    });

    test('compares and hashes by value, so a Map can key on it', () {
      expect(CertificateFingerprint.parse('aa' * 32), a);
      expect(CertificateFingerprint.parse('aa' * 32).hashCode, a.hashCode);
      expect(a, isNot(b));
      expect({a, b, CertificateFingerprint.parse('AA' * 32)}, hasLength(2));
    });

    test('refuses anything that is not a SHA-256 digest', () {
      // A pin the user mistypes must fail where they can see it, not silently
      // become a value nothing will ever match.
      expect(
        () => CertificateFingerprint.parse('ab' * 31),
        throwsArgumentError,
      );
      expect(
        () => CertificateFingerprint.parse('ab' * 33),
        throwsArgumentError,
      );
      expect(
        () => CertificateFingerprint.parse('zz' * 32),
        throwsArgumentError,
      );
      expect(() => CertificateFingerprint.parse(''), throwsArgumentError);
    });

    test('the refusal says what it wanted and what it got, verbatim', () {
      // A user pasting a fingerprint reads this sentence, so it is asserted
      // word for word — prose is mutable source nothing else in the suite
      // looks at, and the mutation gate found two survivors inside it.
      expect(
        () => CertificateFingerprint.parse('ab' * 31),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.invalidValue, 'invalidValue', 'ab' * 31)
              .having((e) => e.name, 'name', 'text')
              .having(
                (e) => e.message,
                'message',
                'is not a SHA-256 certificate fingerprint: expected 64 hex '
                    'characters after removing ":", "-" and spaces, got 62',
              ),
        ),
      );
    });

    test('prints the canonical form and nothing else', () {
      // It goes on screen next to "does this match what your server shows?",
      // so a prefix or a class name in front of it makes the comparison
      // harder for exactly the person doing it by eye.
      expect(a.toString(), a.value);
      expect(a.value, List.filled(32, 'aa').join(':'));
    });
  });

  group('decidePin — the whole table, every combination', () {
    // Pure, total, and exhaustively tested because it is the only part of F15
    // that can be proven without a device: the OS-trusted arm's *wiring* needs
    // a CA-signed certificate for 127.0.0.1, which does not exist.
    //
    // `trustedByOs` is not a guess at either call site.
    // `badCertificateCallback` passes false — dart:io calls it precisely when
    // the chain did not validate, and when a pin is set the client trusts no
    // roots, so every certificate arrives there. `validateCertificate` passes
    // true — it runs after a handshake that already succeeded.
    const cases = <(String, String?, String?, bool, Type)>[
      ('no pin, OS trusts it', null, 'a', true, AcceptCertificate),
      ('no pin, OS does not', null, 'a', false, RejectUntrusted),
      ('pinned, same cert, trusted', 'a', 'a', true, AcceptCertificate),
      ('pinned, same cert, untrusted', 'a', 'a', false, AcceptCertificate),
      ('pinned, different cert, trusted', 'a', 'b', true, RejectChanged),
      (
        'pinned, different cert, untrusted',
        'a',
        'b',
        false,
        RejectChanged,
      ),
      ('no certificate at all, no pin', null, null, true, AcceptCertificate),
      ('no certificate at all, pinned', 'a', null, true, AcceptCertificate),
      ('no cert, pinned, untrusted', 'a', null, false, AcceptCertificate),
      ('no cert, no pin, untrusted', null, null, false, AcceptCertificate),
    ];

    CertificateFingerprint? fp(String? name) => switch (name) {
      'a' => a,
      'b' => b,
      _ => null,
    };

    for (final (name, pinned, observed, trusted, expected) in cases) {
      test(name, () {
        expect(
          decidePin(
            pinned: fp(pinned),
            observed: fp(observed),
            trustedByOs: trusted,
          ).runtimeType,
          expected,
        );
      });
    }

    test('a rejection carries what it saw, so the message can name it', () {
      final changed =
          decidePin(pinned: a, observed: b, trustedByOs: true) as RejectChanged;
      expect(changed.expected, a);
      expect(changed.actual, b);
      final untrusted =
          decidePin(pinned: null, observed: b, trustedByOs: false)
              as RejectUntrusted;
      expect(untrusted.observed, b);
    });

    test('no certificate is accepted, because plain http has none', () {
      // F15 permits plain `http://` for LAN servers. dio calls
      // `validateCertificate` on EVERY response, including a plain-http one,
      // where the certificate is null — measured against dio 5.11.0. Rejecting
      // a null certificate would make every plain-http request fail the moment
      // a pin was stored for some other server.
      expect(
        decidePin(pinned: a, observed: null, trustedByOs: false),
        isA<AcceptCertificate>(),
      );
    });

    test('a decision is exhaustively switchable with no default arm', () {
      String describe(PinDecision d) => switch (d) {
        AcceptCertificate() => 'go',
        RejectUntrusted() => 'ask the user',
        RejectChanged() => 'stop',
      };
      expect(
        describe(decidePin(pinned: a, observed: b, trustedByOs: true)),
        'stop',
      );
    });
  });
}
