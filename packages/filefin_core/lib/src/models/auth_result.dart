import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_result.freezed.dart';
part 'auth_result.g.dart';

/// The body of both `POST /api/login` and `GET /api/me` — upstream's
/// `authResult` (`server.go:447-453`, built by `authResultOf` at `:456`).
///
/// It carries no token: the session travels in the `filefin_session` cookie,
/// which is why nothing here is secret-bearing and §9 does not apply.
///
/// `alias`, `mdlUsername` and `malUsername` are empty far more often than not —
/// the captured fixture has all three empty — so they default rather than being
/// nullable, and a UI reading them never has a null to branch on.
@freezed
abstract class AuthResult with _$AuthResult {
  /// The authenticated user, with every field defaulted (§8).
  const factory AuthResult({
    @Default('') String user,
    @Default(false) bool admin,
    @Default('') String alias,
    @Default('') String mdlUsername,
    @Default('') String malUsername,
  }) = _AuthResult;

  /// Decodes a payload from the server, tolerating unknown keys (§8).
  factory AuthResult.fromJson(Map<String, Object?> json) =>
      _$AuthResultFromJson(json);
}
