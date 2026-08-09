/// The two screens a launch can land on before a library does.
///
/// Split out of `app.dart` at M7.3 when the resuming placeholder pushed it
/// past `just file-size`'s soft limit. They belong together: each is what the
/// user sees when `HomeRoute` has no `LibraryApi` to show, for two different
/// reasons.
library;

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
    this.onSignIn,
    this.onServers,
    super.key,
  });

  /// How many servers `settings.json` holds.
  final int savedCount;

  /// Starts F1's add-a-server flow.
  final VoidCallback onAddServer;

  /// Signs in to the saved server, when there is one.
  final VoidCallback? onSignIn;

  /// Opens F11's picker. Offered from here as well as from the signed-in
  /// shell, because otherwise a user signed out of their second server could
  /// only ever reach their first: [onSignIn] goes to one server, and this is
  /// the only screen with none of them open.
  final VoidCallback? onServers;

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
              Icons.dns_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              savedCount == 0 ? 'No server yet' : 'Signed out',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              savedCount == 0
                  ? 'Add the address of your FileFin server to browse its '
                        'library.'
                  // NOT "a server restart signs everyone out": F3 renews and
                  // replays that transparently and the user never sees this
                  // screen for it. What lands here is having no password to
                  // renew with — after a sign-out, or after one that no longer
                  // works.
                  //
                  // **It said the opposite until M7.4**, and had done since
                  // M7.2 made the store persistent: *"your password is kept
                  // only while this app is running, so a fresh launch starts
                  // signed out"* was true at M3 and became a false statement
                  // about where a credential lives (§9) the moment
                  // `PlatformSecretStore` landed.
                  : 'Sign in again to carry on. Your password is kept in this '
                        "device's secure store, so a launch does not normally "
                        'ask for it.',
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

/// What a launch shows while F2's stored session is being proved.
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
