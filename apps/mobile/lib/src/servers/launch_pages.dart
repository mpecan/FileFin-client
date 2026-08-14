/// The two screens a launch can land on before a library does.
///
/// Split out of `app.dart` when the resuming placeholder pushed it
/// past `just file-size`'s soft limit. They belong together: each is what the
/// user sees when `HomeRoute` has no `LibraryApi` to show, for two different
/// reasons.
library;

import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:flutter/material.dart';

/// What a launch shows before a server is signed in to.
///
/// An empty state rather than a spinner, and the distinction is the point:
/// "nothing here" and "still loading" look identical if you show a spinner for
/// both, and a first launch has nothing to wait for.
class NoServerPage extends StatelessWidget {
  /// Shows the empty state, offering sign-in when [savedCount] is non-zero.
  const NoServerPage({
    required this.onAddServer,
    this.savedCount = 0,
    this.problem,
    this.onSignIn,
    this.onServers,
    super.key,
  });

  /// How many servers `settings.json` holds.
  final int savedCount;

  /// Why the launch did not reach a library, when the reason is not an
  /// ordinary expired session.
  ///
  /// **The screen used to collapse every reason into "Signed out".** A
  /// `CertificatePinMismatch` — the one event pinning exists to make visible —
  /// rendered as an invitation to retype a password, and "your server is off"
  /// read as "you have been signed out". `SessionExpired` keeps the wording
  /// below because that IS what it means, and a session that can be renewed is
  /// renewed silently — so getting here is the rare case. Everything else says
  /// what actually happened.
  final ErrorMessage? problem;

  /// Starts the add-a-server flow.
  final VoidCallback onAddServer;

  /// Signs in to the saved server, when there is one.
  ///
  /// `HomeRoute` withholds it on a `CertificatePinMismatch`, and that is the
  /// point of [problem] rather than a side effect: a changed
  /// certificate a rejection rather than another prompt, so the one thing this
  /// screen must not do is invite a password at a server whose identity has
  /// just failed. [onServers] and [onAddServer] are how a user acts on it.
  final VoidCallback? onSignIn;

  /// Opens the server picker. Offered from here as well as from the signed-in
  /// shell, because otherwise a user signed out of their second server could
  /// only ever reach their first: [onSignIn] goes to one server, and this is
  /// the only screen with none of them open.
  final VoidCallback? onServers;

  /// The wording for the two launches that are not a failure at all.
  ///
  /// NOT *"a server restart signs everyone out"*: a renewal and replays that
  /// transparently and the user never sees this screen for it. What lands here
  /// is having no password to renew with — after a sign-out, or after one that
  /// no longer works.
  ///
  /// **It said the opposite once**, and had done since we added the
  /// store persistent: *"your password is kept only while this app is running,
  /// so a fresh launch starts signed out"* was true and became a false
  /// statement about where a credential lives the moment
  /// `PlatformSecretStore` landed.
  String get _ordinaryDetail => savedCount == 0
      ? 'Add the address of your FileFin server to browse its library.'
      : 'Sign in again to carry on. Your password is kept in this '
            "device's secure store, so a launch does not normally ask for it.";

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('FileFin')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              problem == null ? Icons.dns_outlined : Icons.gpp_maybe_outlined,
              size: 48,
              color: problem == null
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              problem?.title ??
                  (savedCount == 0 ? 'No server yet' : 'Signed out'),
              key: const Key('launch-headline'),
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              problem?.detail ?? _ordinaryDetail,
              key: const Key('launch-detail'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (onSignIn != null)
              FilledButton(onPressed: onSignIn, child: const Text('Sign in')),
            if (onServers != null)
              TextButton(
                onPressed: onServers,
                child: const Text('Servers'),
              ),
            TextButton(
              onPressed: onAddServer,
              child: const Text('Add a server'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// What a launch shows while the stored session is being proved.
///
/// A spinner here and an empty state on a first launch, deliberately: this is
/// the one moment work really is happening and the user has something to wait
/// for. `NoServerPage`'s own test pins the other half.
class ResumingPage extends StatelessWidget {
  /// The launch placeholder.
  const ResumingPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(key: Key('resuming'))),
  );
}
