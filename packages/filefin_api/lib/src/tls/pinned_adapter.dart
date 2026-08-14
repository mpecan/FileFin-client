import 'dart:io';

import 'package:dio/io.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';

/// Wires [pinner] into dio's IO adapter through **both** TLS hooks.
///
/// Two hooks because neither is enough on its own: `connectionFactory` refuses
/// *before any request byte is written* but is skipped by a pooled connection,
/// and `validateCertificate` re-checks a pooled one but only after the request
/// has reached the server. Both route through the same pure `decidePin`.
///
/// **`badCertificateCallback` is deliberately left null** — dart:io's
/// fail-closed default. D19 has the reasoning for all three.
///
/// This is the only place `dart:io` and `HttpClient` appear in the request
/// path, which is what keeps the rest of the package testable without a socket.
IOHttpClientAdapter pinnedAdapter(CertificatePinner pinner) =>
    IOHttpClientAdapter(
      createHttpClient: () => HttpClient()..connectionFactory = pinner.connect,
      validateCertificate: pinner.validate,
    );
