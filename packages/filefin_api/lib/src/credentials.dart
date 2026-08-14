import 'package:meta/meta.dart';

/// A username and password on their way to `POST /api/login`.
///
/// Deliberately **not** `@freezed`: freezed's generated `toString()` prints
/// every field, which must never be logged for a secret-bearing type and which
/// would put a password in the first log line that interpolated one of these.
/// The hand-written [toString] below is the whole reason this is a hand-written
/// class.
@immutable
class Credentials {
  /// The credentials for one account on one server.
  const Credentials({required this.username, required this.password});

  /// The account name. Not a secret, and shown in the UI.
  final String username;

  /// The password. In transit and in the secure store only.
  final String password;

  /// The exact body `auth.go` reads.
  Map<String, Object?> toJson() => {
    'username': username,
    'password': password,
  };

  // No `==`/`hashCode`. Nothing compares two Credentials — they are built,
  // sent, and stored — so writing them would be four untested branches (
  // which is exactly what the mutation gate reported when they were here.

  /// Prints the username and never the password.
  @override
  String toString() => 'Credentials($username, <redacted>)';
}
