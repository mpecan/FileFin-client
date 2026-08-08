/// What `GET /api/state` told us about an address the user typed (F1).
///
/// A separate file from `server_probe.dart`, which builds these, for the same
/// reason `errors.dart` is separate from `error_mapper.dart`: `dead_types`
/// (§5) asks that every sealed variant be constructed **outside** its
/// declaring file, so a variant nothing can produce fails the gate instead of
/// sitting in the tree looking finished.
sealed class ProbeResult {
  /// Allows the variants below to be `const`.
  const ProbeResult();
}

/// A FileFin server, set up and ready to log in to.
final class FileFinServer extends ProbeResult {
  /// The server is FileFin [version] and has an admin account.
  const FileFinServer(this.version);

  /// The running binary's version, e.g. `0.20.3`.
  final String version;

  @override
  String toString() => 'FileFinServer($version)';
}

/// A FileFin server with no admin account yet.
///
/// A dead end for this client rather than a step in a flow: the setup token is
/// deliberately not exposed by `GET /api/state` (`install.go:22-23`) and
/// reaches a browser only through the URL the CLI prints. So the right thing
/// to show is "finish setup in a browser first", never a setup form.
final class FileFinServerNeedsSetup extends ProbeResult {
  /// The server is FileFin [version] but setup is unfinished.
  const FileFinServerNeedsSetup(this.version);

  /// The running binary's version.
  final String version;

  @override
  String toString() => 'FileFinServerNeedsSetup($version)';
}

/// Something answered, and it was not FileFin.
///
/// The common cause is not an attack or a typo but the SPA catch-all: any web
/// server with an `index.html` fallback answers `200 text/html` to
/// `GET /api/state`, and so does FileFin itself for a path it does not route.
final class NotAFileFinServer extends ProbeResult {
  /// Something answered; [reason] says what made it not FileFin.
  const NotAFileFinServer(this.reason);

  /// What disqualified it, phrased for a person reading a dialog.
  final String reason;

  @override
  String toString() => 'NotAFileFinServer($reason)';
}

/// Nothing answered: refused, unresolvable, or too slow.
///
/// Kept apart from [NotAFileFinServer] because the two lead a user to
/// different actions — check the address versus check the network — and
/// collapsing them into one "could not add this server" is how a client makes
/// a wrong port look like a wrong product.
final class ServerUnreachable extends ProbeResult {
  /// Nothing answered; [cause] is the transport failure that says why.
  const ServerUnreachable(this.cause);

  /// The transport failure, so the UI can show the OS's own words.
  final Object cause;

  @override
  String toString() => 'ServerUnreachable($cause)';
}
