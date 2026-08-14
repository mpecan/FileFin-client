import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';

/// Builds the API for one saved server, carrying the certificate it was
/// trusted with (F15).
///
/// **A function rather than something `apiFactory` could do on its own**,
/// because TLS's callbacks are synchronous and `SecretStore` is not, so the pin
/// has to be resolved into memory first (D19) — once, here, rather than at each
/// of the four screens that build a client.
///
/// The pin is read every time rather than cached: accepting a certificate
/// writes it and builds a NEW client, which is what makes acceptance a
/// deliberate act rather than something a running client talks itself into.
Future<LibraryApi> apiForServer(
  AppDependencies deps,
  SavedServer server,
) async => deps.apiFactory(server, pin: await _acceptedPin(deps, server));

/// The pin the user accepted, or null once an unreadable one is forgotten.
///
/// **`parse` is strict and must not be able to brick a launch.** It throws a
/// raw `ArgumentError` on F2's cold-start path, outside the `try` that catches
/// `FileFinApiException` — so one unreadable byte hung every launch for ever,
/// on a bare spinner with no route out.
///
/// **The value can be unreadable through no fault of ours**: the Keychain and
/// Keystore are not our format, and `flutter_secure_storage` documents decrypt
/// failures after an Android backup restore. Deleting rather than ignoring it
/// stops the app running unpinned for ever; F15's prompt is what happens next.
/// `avoid_catching_errors` is wrong here for `FileFinClient._uri`'s reason.
Future<CertificateFingerprint?> _acceptedPin(
  AppDependencies deps,
  SavedServer server,
) async {
  final stored = await deps.secrets.read(server.id, SecretKind.certificatePin);
  if (stored == null) return null;
  try {
    return CertificateFingerprint.parse(stored);
    // The value came out of a platform store, not a caller's hand — see above.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    await deps.secrets.delete(server.id, SecretKind.certificatePin);
    return null;
  }
}
