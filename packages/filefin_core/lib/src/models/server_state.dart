import 'package:freezed_annotation/freezed_annotation.dart';

part 'server_state.freezed.dart';
part 'server_state.g.dart';

/// `GET /api/state` — the reachability and version probe (`install.go:24`).
///
/// Unauthenticated, and the only endpoint that is. F1 accepts a server only
/// when the response is `application/json` **and** decodes to an object
/// carrying both of these keys: the server registers an SPA catch-all outside
/// its route table, so a `200` proves nothing on its own.
///
/// The setup token is deliberately absent upstream (`install.go:22-23`) — a
/// client cannot drive first-run setup and should not try.
@freezed
abstract class ServerState with _$ServerState {
  /// The probe response, every field defaulted so a partial body decodes.
  const factory ServerState({
    @Default(false) bool needsSetup,
    @Default('') String version,
  }) = _ServerState;

  /// Decodes a payload from the server, tolerating unknown keys (§8).
  factory ServerState.fromJson(Map<String, Object?> json) =>
      _$ServerStateFromJson(json);
}
