import 'package:meta/meta.dart';

/// A personal access token on its way to an `Authorization: Bearer` header.
///
/// Deliberately **not** `@freezed`, for the same reason as `Credentials`:
/// freezed's generated `toString()` prints every field, which must never
/// happen for a secret-bearing type.
@immutable
class ApiToken {
  /// One token, minted server-side and pasted in by the user.
  const ApiToken(this.value);

  /// The raw token, exactly as `auth.go` compares it. In transit and in the
  /// secure store only.
  final String value;

  /// The header FileFin's bearer-auth path reads.
  Map<String, String> toHeader() => {'Authorization': 'Bearer $value'};

  /// Prints neither the token nor its length, which would narrow a guess.
  @override
  String toString() => 'ApiToken(<redacted>)';
}
