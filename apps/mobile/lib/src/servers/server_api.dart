import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';

/// Builds the API for one saved server, carrying the certificate it was
/// trusted with (F15).
///
/// **A function rather than something `apiFactory` could do on its own**, and
/// the reason is a platform constraint rather than taste: TLS's callbacks are
/// synchronous and cannot await a secret-store read, so
/// `FileFinClient.forServer` takes the pin already resolved into memory
/// (`certificate_pinner.dart`). The factory is synchronous and `SecretStore`
/// is not, so somebody has to do the read first — once, here, rather than at
/// each of the four screens that build a client.
///
/// The pin is read every time rather than cached: accepting a certificate
/// writes it and builds a NEW client, which is precisely what makes acceptance
/// a deliberate act instead of something a running client can talk itself into.
Future<LibraryApi> apiForServer(
  AppDependencies deps,
  SavedServer server,
) async {
  final stored = await deps.secrets.read(server.id, SecretKind.certificatePin);
  return deps.apiFactory(
    server,
    // `parse` rather than a tolerant read. A value that is not a fingerprint
    // can only be one we wrote wrong, and a pin that quietly matches nothing
    // is a pin that silently stops protecting anything.
    pin: stored == null ? null : CertificateFingerprint.parse(stored),
  );
}
