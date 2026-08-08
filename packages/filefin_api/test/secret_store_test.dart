import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

const server = ServerId('home');

void main() {
  late InMemorySecretStore secrets;

  setUp(() => secrets = InMemorySecretStore());

  test('lays keys out exactly as SPEC.md §7 says', () {
    expect(secretKeyFor(server, SecretKind.session), 'filefin/home/session');
    expect(
      secretKeyFor(server, SecretKind.password),
      'filefin/home/password',
    );
    expect(
      secretKeyFor(server, SecretKind.certificatePin),
      'filefin/home/certpin',
    );
  });

  test('namespaces by server, so two servers never share a secret', () async {
    const other = ServerId('work');
    await secrets.write(server, SecretKind.password, 'one');
    await secrets.write(other, SecretKind.password, 'two');
    expect(await secrets.read(server, SecretKind.password), 'one');
    expect(await secrets.read(other, SecretKind.password), 'two');
    await secrets.delete(server, SecretKind.password);
    expect(await secrets.read(server, SecretKind.password), isNull);
    expect(await secrets.read(other, SecretKind.password), 'two');
  });

  test('deleting something that was never there is not an error', () async {
    await secrets.delete(server, SecretKind.session);
    expect(await secrets.read(server, SecretKind.session), isNull);
  });

  test('an implementation that forgets to redact still cannot leak', () async {
    // The property `abstract base class` buys: `base` forces every subtype to
    // EXTEND rather than implement, so the redacting `toString` on the base is
    // inherited rather than merely recommended. This store deliberately does
    // not override it — which is what an implementation written in a hurry
    // looks like — and it still prints nothing.
    final forgetful = ForgetfulSecretStore();
    await forgetful.write(server, SecretKind.password, 'hunter2');
    expect(forgetful.toString(), isNot(contains('hunter2')));
    expect(forgetful.toString(), 'ForgetfulSecretStore(<redacted>)');
  });

  test('a secret store prints its size and nothing else', () async {
    await secrets.write(server, SecretKind.password, 'hunter2');
    expect(secrets.toString(), isNot(contains('hunter2')));
    expect(secrets.toString(), 'InMemorySecretStore(1 entry, <redacted>)');
    await secrets.write(server, SecretKind.session, 's');
    expect(secrets.toString(), 'InMemorySecretStore(2 entries, <redacted>)');
  });
}

/// A `SecretStore` that overrides nothing it is not forced to.
final class ForgetfulSecretStore extends SecretStore {
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
}
