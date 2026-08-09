import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SPEC.md §7's secure store, backed by the Keychain and the Keystore (F2, §9).
///
/// **A persistence decorator around [InMemorySecretStore], not a replacement
/// for it**, which is the shape `secret_store.dart` and `docs/architecture.md`
/// have both been promising since M2. Reads hit memory first and fall through
/// to the platform on a miss, populating memory on the way back; writes and
/// deletes go to both.
///
/// **Memory-first is a correctness requirement rather than an optimisation.**
/// F3 renews a session in the middle of a 401 retry, and on iOS a Keychain read
/// can block on the device being unlocked — so a re-auth that had to await the
/// platform store is a re-auth that can stall a request indefinitely. The
/// in-memory copy is what makes the retry synchronous in practice; the platform
/// copy is what makes a cold start silent.
///
/// The key layout is not repeated here. `secretKeyFor` is the only place
/// `filefin/{serverId}/session|password|certpin` exists, and this class hands
/// the platform exactly what it returns.
///
/// §13: there is no earlier layout, so there is no migration and no fallback
/// branch reading what an earlier build wrote.
final class PlatformSecretStore extends SecretStore {
  /// A store over the platform's own secure storage.
  PlatformSecretStore();

  /// Default options on both platforms, and the choice is recorded rather than
  /// inherited: `synchronizable: false` keeps a password off iCloud Keychain,
  /// and the Android side is AES-GCM with a Keystore-wrapped key. The iOS
  /// accessibility class is `whenUnlocked`, which is the strictest of the
  /// non-passcode options; `docs/verification-backlog.md` carries the device
  /// experiment for what the OS actually did with it, because a fake platform
  /// channel can only prove the arguments crossed.
  final FlutterSecureStorage _platform = const FlutterSecureStorage();

  final InMemorySecretStore _memory = InMemorySecretStore();

  @override
  Future<String?> read(ServerId server, SecretKind kind) async {
    final cached = await _memory.read(server, kind);
    if (cached != null) return cached;
    final stored = await _platform.read(key: secretKeyFor(server, kind));
    if (stored != null) await _memory.write(server, kind, stored);
    return stored;
  }

  @override
  Future<void> write(ServerId server, SecretKind kind, String value) async {
    await _memory.write(server, kind, value);
    await _platform.write(key: secretKeyFor(server, kind), value: value);
  }

  @override
  Future<void> delete(ServerId server, SecretKind kind) async {
    await _memory.delete(server, kind);
    await _platform.delete(key: secretKeyFor(server, kind));
  }

  /// Prints nothing it holds (§9, NF4).
  ///
  /// Explicit rather than inherited from [SecretStore], because
  /// `just constitution`'s `secret_tostring` reads the class body it is looking
  /// at and cannot see a superclass — and an override that is right for the
  /// wrong reason is still the one a future field needs.
  @override
  String toString() => 'PlatformSecretStore(<redacted>)';
}
