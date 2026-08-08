import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';

import 'stub_server.dart';

/// The saved server every client test talks to.
const serverId = ServerId('home');

/// The account every client test logs in as.
const creds = Credentials(username: 'testuser', password: 'TestPassw0rd!23');

/// Counts `POST /api/login` at the transport level.
///
/// A real interceptor on the injected `authDio` rather than a counter inside
/// `SessionManager`: dependency injection is what lets a test observe the thing
/// that matters without the production class growing a field that exists only
/// to be looked at. `just it` counts the same way.
class LoginCounter extends Interceptor {
  /// How many logins have gone out.
  int count = 0;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path.endsWith('/api/login')) count++;
    handler.next(options);
  }
}

/// A client wired the way `forServer` wires one, but with injected `Dio`s.
///
/// Shared by both client suites rather than copied into each: two copies of
/// this much setup is what `just dupes` exists to notice, and a harness that
/// drifts between two files is worse than one that is slightly general.
class ClientHarness {
  ClientHarness._(this.client, this.logins);

  /// Builds a client against [stub] with a short [timeout].
  factory ClientHarness.build(
    StubServer stub,
    FileFinUrls urls,
    SecretStore secrets, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final jar = DefaultCookieJar();
    final logins = LoginCounter();
    final authDio =
        Dio(fileFinBaseOptions(baseUrl: stub.baseUrl, timeout: timeout))
          ..interceptors.add(CookieManager(jar))
          ..interceptors.add(logins);
    final dio = Dio(
      fileFinBaseOptions(baseUrl: stub.baseUrl, timeout: timeout),
    );
    return ClientHarness._(
      FileFinClient(
        server: serverId,
        dio: dio,
        authDio: authDio,
        jar: jar,
        urls: urls,
        sessions: SessionManager(
          authDio: authDio,
          urls: urls,
          jar: jar,
          secrets: secrets,
          server: serverId,
        ),
      ),
      logins,
    );
  }

  /// The client under test.
  final FileFinClient client;

  /// The login counter on its `authDio`.
  final LoginCounter logins;
}

/// Serves `POST /api/login`, handing out a distinguishable cookie each time.
///
/// `sess-1`, `sess-2`, … so a test can assert *which* session a request
/// carried rather than merely that it carried one — which is the difference
/// between proving the replay used the new cookie and assuming it did.
void serveLogin(StubServer stub, FileFinUrls urls) {
  var issued = 0;
  stub.on(urls.login.path, (_) {
    issued++;
    return StubResponse.json(
      <String, Object?>{'user': 'testuser', 'admin': true},
      headers: {
        'set-cookie':
            'filefin_session=sess-$issued; Path=/; HttpOnly; SameSite=Lax',
      },
    );
  });
}
