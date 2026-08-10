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
) async => deps.apiFactory(server, pin: await _acceptedPin(deps, server));

/// The pin the user accepted, or null once an unreadable one is forgotten.
///
/// **`parse` is strict on purpose and it must not be able to brick a launch.**
/// A value that is not a fingerprint is not something to read tolerantly — a
/// pin that quietly matches nothing is a pin that has silently stopped
/// protecting anything — but `parse` throws a raw `ArgumentError`, and this
/// call sits on F2's cold-start path OUTSIDE `HomeRoute._resume`'s `try`, which
/// catches only `FileFinApiException`. One unreadable byte therefore hung every
/// launch for ever: `_resuming` never cleared, `ResumingPage` is a bare spinner
/// with no button, `_launched` latches, and there was no route left to the
/// picker, to add-server or to sign-out.
///
/// **"It can only be a value we wrote wrong" was true of our writes and false
/// of the store they live in.** `settings.json` is ours; the Keychain and the
/// Keystore are not, and `flutter_secure_storage` documents decrypt failures on
/// Android after a backup restore or a keystore reset. §13 gives us no
/// migration path and needs none — this is not an older format, it is an
/// unreadable value.
///
/// Deleting it rather than ignoring it is what stops the app running unpinned
/// for ever against a byte string it will never read again. What happens next
/// is F15's trust-on-first-use prompt, which is a decision somebody takes
/// rather than a protection that quietly lapsed.
///
/// `avoid_catching_errors` is right nearly everywhere and wrong here, for the
/// reason `FileFinClient._uri` records: the rejected value came out of a
/// platform store rather than out of a caller's hand, so this is the boundary
/// that turns it into a recoverable outcome instead of a crash.
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
