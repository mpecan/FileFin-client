import 'dart:io';

import 'package:dio/io.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';

/// Wires [pinner] into dio's IO adapter through **both** TLS hooks.
///
/// Two hooks, because they answer different questions and neither is enough:
///
/// - `connectionFactory` owns the handshake, so a refusal happens *before any
///   request byte is written* — but dart:io calls it once per **connection**,
///   and a pooled connection skips it entirely.
/// - `validateCertificate` runs per **response**, so it re-checks a pooled
///   connection — but only after the request has already reached the server.
///
/// Together they give "refuse before sending" on every new connection and
/// "still the same certificate" on every reused one. Both route through the
/// same pure `decidePin`, so there is exactly one policy and it is the one the
/// table test proves.
///
/// **`badCertificateCallback` is deliberately left null**, which is dart:io's
/// fail-closed default. Setting `connectionFactory` takes the handshake away
/// from dart:io for every direct connection, so the callback would be dead code
/// on the path that matters (§5) — and on the one path that could still reach
/// it, an https proxy tunnel this package never configures, a null callback
/// refuses rather than consulting a hook that is handed the wrong certificate.
///
/// This is also the only place `dart:io` and `HttpClient` appear in the request
/// path, which is what keeps the rest of the package testable without a socket.
IOHttpClientAdapter pinnedAdapter(CertificatePinner pinner) =>
    IOHttpClientAdapter(
      createHttpClient: () => HttpClient()..connectionFactory = pinner.connect,
      validateCertificate: pinner.validate,
    );
