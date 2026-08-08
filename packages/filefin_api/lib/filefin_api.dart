/// The FileFin HTTP client.
///
/// Everything that touches a socket lives here (CLAUDE.md §6): `filefin_core`
/// holds the types, the URLs and the rules, `apps/mobile` draws, and this
/// package is the only layer that knows what a `401` means (SPEC.md §5.1).
///
/// It is **pure Dart — Flutter-free**, which is a structural decision rather
/// than a preference. `just test`, `just coverage` and `just mutants` all run
/// `dart test` per package; a Flutter package needs `flutter test` and a
/// different coverage path, so a Flutter dependency here would force all three
/// gates to grow a branch at M2. It is also why credential persistence arrives
/// as an injected port rather than as `flutter_secure_storage`, whose plugin
/// has no VM implementation and would make every F3 unit test mock the one
/// layer that matters. `dart:io` is fine and is required for F15.
///
/// This barrel is the package's entire public surface: `lib/src/**` is private
/// by convention, so a symbol not exported here has no consumer outside the
/// library and is dead by §5.
library;

export 'src/error_mapper.dart';
export 'src/errors.dart';
export 'src/json_response.dart';
export 'src/probe_result.dart';
export 'src/server_probe.dart';
export 'src/tls/certificate_pinner.dart';
export 'src/tls/fingerprint.dart';
export 'src/tls/pin_decision.dart';
export 'src/tls/pinned_adapter.dart';
export 'src/transport.dart';
