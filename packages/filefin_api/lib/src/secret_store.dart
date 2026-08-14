import 'package:filefin_core/filefin_core.dart';

/// The three things this client keeps per server that must never be logged,
/// written to a settings file, or held in unencrypted storage (§9, NF4).
enum SecretKind {
  /// The `filefin_session` cookie value.
  session('session'),

  /// The account password, kept so F3 can re-authenticate silently (F2).
  ///
  /// Storing a password is a real decision and SPEC.md D5 records it: server
  /// sessions die with the process (L1), so re-typing a password on a phone
  /// every time the server restarts is not something a person will tolerate.
  password('password'),

  /// The SHA-256 certificate fingerprint the user accepted (F15).
  ///
  /// **It is integrity data, not a secret**, and it is here for the same
  /// reason a public key would be: it is worthless to an attacker who reads it
  /// and catastrophic to one who *writes* it. Nothing in this repository
  /// should ever "optimise" it into `settings.json`, which is a plain file any
  /// app on a rooted device can edit.
  certificatePin('certpin');

  const SecretKind(this.key);

  /// The token that appears in the storage key.
  final String key;
}

/// SPEC.md §7's secure-store key layout, in exactly one place.
///
/// `filefin/{serverId}/session|password|certpin`. One function rather than a
/// format string at each call site, because a layout written twice is a layout
/// that will be written differently — and the failure mode is a credential
/// that silently cannot be found rather than an error anybody sees.
String secretKeyFor(ServerId server, SecretKind kind) =>
    'filefin/${server.value}/${kind.key}';

/// Where credentials live. Implemented by the platform, injected here.
///
/// **A port rather than a `flutter_secure_storage` call**, because this package
/// is Flutter-free: the plugin throws `MissingPluginException` under
/// `dart test`, so depending on it would make every F3 unit test mock precisely
/// the layer that matters. `apps/mobile` supplies the Keychain/Keystore side.
///
/// `abstract base class` rather than an interface (D22) is what makes the
/// redacting [toString] below *inherited* rather than merely recommended (§9).
abstract base class SecretStore {
  /// Allows implementations to be `const`.
  const SecretStore();

  /// The stored value, or null when there is none.
  Future<String?> read(ServerId server, SecretKind kind);

  /// Stores [value], replacing anything already there.
  Future<void> write(ServerId server, SecretKind kind, String value);

  /// Removes the value. Removing something absent is not an error.
  Future<void> delete(ServerId server, SecretKind kind);

  /// Never prints a stored value (§9).
  ///
  /// Concrete on the base so no implementation can leak by forgetting. It is
  /// also what `secret_tostring` asks for, and the gate is right to ask: a
  /// store whose `toString` printed its contents would put every password in
  /// the first log line that interpolated it.
  @override
  String toString() => '$runtimeType(<redacted>)';
}

/// The process-lifetime credential cache.
///
/// **Not a stub, and not a test double.** F3 needs the password in memory for
/// the life of the process whatever the persistence story is — a re-auth
/// cannot await a Keychain prompt in the middle of a 401 retry — so this is
/// the production cache, and M7's platform store is a persistence decorator
/// around it. It is constructed by every unit test and by every `just it`
/// suite, so §5's "has a consumer" holds today rather than eventually.
///
/// **What it does not do is survive an app restart.** Nothing at M2 proves a
/// password does; STATE.md says so rather than letting the port's existence
/// imply it.
final class InMemorySecretStore extends SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(ServerId server, SecretKind kind) async =>
      _values[secretKeyFor(server, kind)];

  @override
  Future<void> write(ServerId server, SecretKind kind, String value) async =>
      _values[secretKeyFor(server, kind)] = value;

  @override
  Future<void> delete(ServerId server, SecretKind kind) async =>
      _values.remove(secretKeyFor(server, kind));

  @override
  String toString() =>
      'InMemorySecretStore(${_values.length} '
      '${_values.length == 1 ? 'entry' : 'entries'}, <redacted>)';
}
