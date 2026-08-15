/// What `FileFinClient` needs from a signed-in server, independent of
/// whether the credential behind it is a password or a token.
///
/// **A port, like `SecretStore`**: `abstract base class` so the redacting
/// [toString] is inherited rather than merely recommended, and so a future
/// third implementation cannot forget it. `SessionManager` and
/// `TokenAuthSession` are the two today; each also carries members the other
/// has no use for (`login`, `generation`) that deliberately stay off this
/// interface rather than being padded in with a default nobody would call.
abstract base class AuthSession {
  /// Allows implementations to be `const`.
  const AuthSession();

  /// Ends this credential's server-side effect if it has one, and forgets
  /// everything stored locally for it.
  Future<void> forget();

  /// The header(s) a raw caller — libmpv — must send to authenticate as this
  /// session right now, or null when there is nothing to send.
  Future<Map<String, String>?> headers();

  /// Restores this session on a cold start, silently recovering when this
  /// credential kind supports it.
  ///
  /// A single method rather than "try restore, catch and renew" left in the
  /// caller: that shape is specific to a password's two-tier
  /// session-then-credential renewal, and a token has no second tier to fall
  /// back to.
  Future<void> resume();

  /// Prints no credential, no session value and no username.
  @override
  String toString() => '$runtimeType(<redacted>)';
}
