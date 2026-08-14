/// The FileFin HTTP client.
///
/// Everything that touches a socket lives here, and this is the only
/// layer that knows what a `401` means. **Pure Dart —
/// Flutter-free**, structurally so; `docs/architecture.md` has the argument.
/// This barrel is the entire public surface: a symbol not exported here is
/// dead code.
///
/// **`CancelToken` is dio's, re-exported so `apps/mobile` never imports dio.**
/// A cancel token is on every endpoint while `app_no_raw_http` refuses
/// `package:dio/` under `apps/*/lib`; re-exporting the one type the app
/// legitimately needs is what makes that refusal live-able.
library;

export 'package:dio/dio.dart' show CancelToken;

export 'src/auth_interceptor.dart';
export 'src/client.dart';
export 'src/credentials.dart';
export 'src/error_mapper.dart';
export 'src/errors.dart';
export 'src/json_response.dart';
export 'src/playback_session.dart';
export 'src/probe_result.dart';
export 'src/secret_store.dart';
export 'src/server_probe.dart';
export 'src/session.dart';
export 'src/tls/certificate_pinner.dart';
export 'src/tls/fingerprint.dart';
export 'src/tls/pin_decision.dart';
export 'src/tls/pinned_adapter.dart';
export 'src/transport.dart';
