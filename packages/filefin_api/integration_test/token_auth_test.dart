@Timeout(Duration(seconds: 30))
library;

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// A real server's `auth.go`, not a stub, is the only thing that can prove a
/// bearer header was actually accepted rather than merely sent. The token
/// itself is minted through the seeded account's own session, mirroring how
/// a user pastes one in from Settings - this client never mints its own
/// (D26).
void main() {
  late FileFinTestServer server;

  setUp(() async {
    server = await startServer();
  });

  /// Signs in as [seededCredentials] and returns a `Dio` carrying that
  /// session, for the one call this client deliberately does not wrap -
  /// `POST /api/profile/tokens` is server-Settings territory, not something
  /// `FileFinClient` exposes.
  Future<Dio> signInRaw() async {
    final owner = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(owner.close);
    await owner.login(seededCredentials);
    return Dio(BaseOptions(baseUrl: server.baseUrl.toString()))
      ..interceptors.add(CookieManager(owner.jar));
  }

  Future<({String id, String token})> mintToken(Dio raw, String label) async {
    final response = await raw.post<Map<String, dynamic>>(
      '/api/profile/tokens',
      data: {'label': label},
      options: Options(contentType: Headers.jsonContentType),
    );
    return (
      id: response.data!['id']! as String,
      token: response.data!['token']! as String,
    );
  }

  test(
    'a token minted from Settings authenticates a real client end to end',
    () async {
      final minted = await mintToken(await signInRaw(), 'integration');
      final tokenClient = FileFinClient.forTokenServer(
        server: const ServerId('integration-token'),
        baseUrl: server.baseUrl,
        secrets: InMemorySecretStore(),
      );
      addTearDown(tokenClient.close);

      final me = await tokenClient.signInWithToken(ApiToken(minted.token));
      expect(me.user, seededCredentials.username);

      final categories = await tokenClient.categories();
      expect(categories, isNotEmpty, reason: 'the seeded library has two');
    },
  );

  test('a revoked token is InvalidToken against the real server', () async {
    final raw = await signInRaw();
    final minted = await mintToken(raw, 'revoke-me');
    await raw.delete<void>('/api/profile/tokens/${minted.id}');

    final tokenClient = FileFinClient.forTokenServer(
      server: const ServerId('integration-token-revoked'),
      baseUrl: server.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(tokenClient.close);

    await expectLater(
      tokenClient.signInWithToken(ApiToken(minted.token)),
      throwsA(isA<InvalidToken>()),
    );
  });
}
