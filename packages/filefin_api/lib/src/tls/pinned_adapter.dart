import 'dart:io';

import 'package:dio/io.dart';
import 'package:filefin_api/src/tls/certificate_pinner.dart';

/// Wires [pinner] into dio's IO adapter through **both** TLS hooks.
///
/// Two hooks, because they answer different questions and neither is enough:
///
/// - `badCertificateCallback` runs during the handshake, so a refusal happens
///   *before any request bytes are sent* — but it is per **connection**, and a
///   pooled connection skips it entirely.
/// - `validateCertificate` runs per **response**, so it re-checks a pooled
///   connection — but only after the request has already reached the server.
///
/// Together they give "refuse before sending" on every new connection and
/// "still the same certificate" on every reused one. Both route through the
/// same pure `decidePin`, so there is exactly one policy and it is the one the
/// table test proves.
///
/// This is also the only place `dart:io` and `HttpClient` appear in the request
/// path, which is what keeps the rest of the package testable without a socket.
IOHttpClientAdapter pinnedAdapter(CertificatePinner pinner) =>
    IOHttpClientAdapter(
      createHttpClient: () =>
          HttpClient(context: pinner.securityContext)
            ..badCertificateCallback = pinner.allowBadCertificate,
      validateCertificate: pinner.validate,
    );
