part of 'player_page.dart';

// The panels and banners the player screen draws, split out of
// `player_page.dart` at M7.6 when F14's binder took that file over `just
// file-size`'s 400-line soft limit — and a gate warning may fall or hold, never
// rise. A `part` rather than a library for the reason `player_failure.dart` is
// one: three of these five are private to the screen, and making them public to
// move them would trade a size warning for five new public members with one
// consumer each.

/// The persistent banner D10 requires when unverified playback is on.
///
/// **A banner rather than a one-time dialog, and the difference is the point:**
/// what has been given up is ongoing, not a single act. It names exactly what
/// is unprotected instead of saying "insecure".
class UnverifiedTlsBanner extends StatelessWidget {
  /// Shows the standing warning.
  const UnverifiedTlsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // The scheme read once. Two `Theme.of(context)` calls in one build is a
    // small thing, and at M4 this hoist was load-bearing for a second reason:
    // collapsing the `TextStyle(...)` onto one line also removed the only
    // mutant in this file that no assertion could kill. **That is no longer
    // what protects it** — M4.R/G5 narrowed the three argument-swap rules so
    // they cannot match a run of closing parentheses at all, which is a fix in
    // `mutation_rules.xml` rather than one enforced by `dart format`. Measured:
    // un-hoisted, the file goes 33 → 36 mutants under the old rules and stays
    // at 30 under the new ones. The hoist stays because it reads better.
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Text(
        'Unverified playback is on for this server. The player checks no '
        'certificate, so the session cookie may reach a server whose identity '
        'nobody verified.',
        style: TextStyle(color: scheme.onErrorContainer),
      ),
    );
  }
}

/// F13's confirmation, naming the real size.
class MeteredPrompt extends StatelessWidget {
  /// Asks about [bytes].
  const MeteredPrompt({
    required this.bytes,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  /// The file's actual size.
  final int bytes;

  /// Play anyway.
  final VoidCallback onConfirm;

  /// Go back.
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.signal_cellular_alt, size: 48),
          const SizedBox(height: 16),
          Text(
            'This file is ${humanSize(bytes)} and you are on a metered '
            'connection.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onConfirm, child: const Text('Play anyway')),
          TextButton(onPressed: onCancel, child: const Text('Not now')),
        ],
      ),
    ),
  );
}

/// F12's answer to a `415`: name the cause, name who can change it.
///
/// It says what transcoding IS, because "transcoding is disabled" means
/// nothing to most people looking at a film that will not play, and it says
/// plainly that no setting in this app will help — the alternative is a user
/// hunting through their own settings for something that is not there.
class _UnplayablePanel extends StatelessWidget {
  const _UnplayablePanel({required this.server});

  final SavedServer server;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.movie_filter_outlined,
            size: 48,
            color: Colors.white70,
          ),
          const SizedBox(height: 16),
          Text(
            // "The file you asked for", not "This file": after a refused
            // `next()` the panel is about the episode the user just asked for
            // and NOT about the one they were watching a second ago, and
            // "this" cannot tell them apart (M5.R/C-F6).
            'The file you asked for needs transcoding, and "${server.name}" '
            'has it turned off.',
            textAlign: TextAlign.center,
            // No explicit size, matching `_RefusalPanel` and `MeteredPrompt`.
            // A hard-coded `fontSize: 18` also fixed the type scale against the
            // system font setting, which is exactly what backlog row 13 exists
            // about — and it was the one surviving mutant in this file, because
            // nothing can assert a point size that carries no meaning.
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            // "turn it on", not "back on": nothing here knows it was ever
            // on, and a server that shipped with it off has never had it.
            'The server converts formats a player cannot read as they are. '
            'With that turned off there is nothing to play — nothing this app '
            'can change will help, so someone with admin access to the server '
            'has to turn it on.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}

class _RefusalPanel extends StatelessWidget {
  const _RefusalPanel({required this.reason, required this.server});

  final RefuseReason reason;
  final SavedServer server;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block, size: 48, color: Colors.white70),
          const SizedBox(height: 16),
          Text(
            switch (reason) {
              RefuseReason.offline =>
                'There is no connection, so there is nothing to stream over.',
              RefuseReason.wifiOnlyOnMetered =>
                'You are on a metered connection and "${server.name}" is set '
                    'to Wi-Fi only. Change it in playback settings to play '
                    'here.',
              RefuseReason.unverifiablePlaybackTls =>
                '"${server.name}" uses a certificate only this app trusts, and '
                    'the player cannot check it. Playing anyway would send the '
                    'session cookie to a server whose identity nobody '
                    'verified — turn on unverified playback for this server if '
                    'you accept that.',
            },
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    ),
  );
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message, this.onSignIn});

  final String message;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.errorContainer,
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
        if (onSignIn != null)
          TextButton(onPressed: onSignIn, child: const Text('Sign in')),
      ],
    ),
  );
}

/// Reporting stopped because the server rejected the report itself.
///
/// Non-blocking on purpose: playback carries on, and the only thing lost is the
/// resume pointer for this session.
class _ReportStoppedBanner extends StatelessWidget {
  const _ReportStoppedBanner();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    padding: const EdgeInsets.all(8),
    child: const Text(
      'Progress is no longer being saved: this item changed on the server. '
      'Go back and open it again.',
    ),
  );
}
