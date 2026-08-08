import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:filefin_api/filefin_api.dart';

/// The JSON body every stub answers with, and its exact byte length.
const _body = '{"needsSetup":false,"version":"0.20.3"}';

/// A real TLS server on loopback, serving `test/support/certs/server_<name>`.
///
/// Real handshake, real `X509Certificate` — the only part of F15 a stub would
/// render meaningless, because what is under test is precisely what the TLS
/// stack does with our two hooks.
///
/// **It is a raw `SecureServerSocket` and speaks HTTP/1.1 by hand, rather than
/// an `HttpServer`, for one reason: [bytesReceived].** "Blocking" is a claim
/// about bytes, and the M2 review found a pin that refused with the right
/// exception type *after* 106 bytes — a `GET` carrying the session cookie —
/// had reached an impostor. An `HttpServer` only surfaces requests it managed
/// to parse, so a test written against one asserts what the peer *understood*
/// rather than what it *received*. The TLS layer hands this listener decrypted
/// application data only, so every byte counted here is a byte of ours the peer
/// could read.
///
/// It exists because the `filefin` binary has **no TLS listener at all** (no
/// `ListenAndServeTLS`, no certificate flag anywhere in `internal/` or `cmd/`,
/// verified at v0.20.3): TLS is a reverse-proxy concern upstream. So SPEC.md
/// §10's "a self-signed server connects only after explicit accept" is met
/// against a Dart TLS server rather than a real FileFin, and STATE.md and
/// docs/risks.md say so.
class TlsStub {
  TlsStub._(this._server);

  final SecureServerSocket _server;

  /// Every path the server was actually asked for.
  final List<String> seen = [];

  /// Every request head the server received, verbatim.
  ///
  /// Asserted **empty** after a refusal, and searched for the session cookie:
  /// "no credential left the device" is a statement about these strings.
  final List<String> received = [];

  /// Application bytes the peer could read, handshake excluded.
  int bytesReceived = 0;

  static Future<TlsStub> serving(String name) async {
    final context = SecurityContext()
      ..useCertificateChain('test/support/certs/server_$name.crt')
      ..usePrivateKey('test/support/certs/server_$name.key');
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    final stub = TlsStub._(server);
    // A handshake this server's peer abandons arrives as a stream error. It is
    // the expected outcome of half these tests, not a failure.
    server.listen(stub._serve, onError: (Object _) {});
    return stub;
  }

  Uri get baseUrl => Uri.parse('https://127.0.0.1:${_server.port}');

  Future<void> close() => _server.close();

  void _serve(SecureSocket socket) {
    var pending = '';
    socket.listen(
      (data) {
        bytesReceived += data.length;
        pending += utf8.decode(data, allowMalformed: true);
        // Keep-alive by hand: one canned answer per complete head, so the
        // pooled-connection test really does reuse one socket.
        while (pending.contains('\r\n\r\n')) {
          final end = pending.indexOf('\r\n\r\n') + 4;
          final head = pending.substring(0, end);
          pending = pending.substring(end);
          received.add(head);
          seen.add(head.split(' ').elementAtOrNull(1) ?? '');
          socket.write(
            'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n'
            'Content-Length: ${_body.length}\r\n\r\n$_body',
          );
        }
      },
      onError: (Object _) {},
      cancelOnError: true,
    );
  }
}

/// The fingerprint of a committed test certificate, read from the PEM on disk.
///
/// Computed rather than hard-coded, so regenerating a pair is one command
/// instead of a hunt through assertions — and so the assertions compare our
/// digest against the certificate itself rather than against a number someone
/// once pasted. `README.md` records the `openssl x509 -fingerprint -sha256`
/// output that proves the two agree.
///
/// The DER is the PEM's base64 payload. It is extracted here rather than taken
/// from an `X509Certificate`, because dart:io only hands one over during a live
/// handshake — which is the thing under test.
///
/// **Only the FIRST block**, which is what makes the chain fixtures usable:
/// `server_c.crt` and `server_d.crt` are `[leaf, CA]` full chains, and a helper
/// that concatenated both DERs would hash a value no certificate has.
CertificateFingerprint pemFingerprint(String path) {
  final blocks = RegExp(
    '-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----',
    dotAll: true,
  ).allMatches(File(path).readAsStringSync());
  return CertificateFingerprint.fromDer(
    base64.decode(blocks.first.group(1)!.replaceAll(RegExp(r'\s'), '')),
  );
}

/// The leaf fingerprint of `server_<name>`.
CertificateFingerprint derFingerprint(String name) =>
    pemFingerprint('test/support/certs/server_$name.crt');

/// The private CA that signed `server_c` and `server_d`.
CertificateFingerprint caFingerprint() =>
    pemFingerprint('test/support/certs/ca.crt');
