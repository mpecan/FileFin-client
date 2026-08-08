import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:flutter/material.dart';

/// The one rendering of a failure, used by every screen.
///
/// One widget rather than three copies is what keeps `just dupes` off the tree
/// (5% / 15 lines / 50 tokens), and it is also what makes "explain the failure
/// in the user's terms" a property of the app rather than of whichever screen
/// someone wrote most recently.
class ErrorPanel extends StatelessWidget {
  /// Renders [error], offering retry and sign-in only where they make sense.
  const ErrorPanel({
    required this.error,
    this.onRetry,
    this.onSignIn,
    super.key,
  });

  /// The failure, untranslated.
  final FileFinApiException error;

  /// Called when the user asks to try again. Shown only when the failure is
  /// [ErrorMessage.retryable] — a retry button on a rate-limit refusal invites
  /// mashing it against a limiter that locks the account for fifteen minutes.
  final VoidCallback? onRetry;

  /// Called when the user asks to sign in again (F3's last resort).
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final message = describeApiError(error);
    // A ListView rather than a bare Column, and a test found the reason: a
    // long detail overflowed by 28 pixels at 800x600. Every message here is a
    // sentence or three, the panel is shown at whatever size the screen it
    // replaces was, and a user with large text has less room still — so the
    // content has to scroll rather than be clipped with a striped bar.
    // `shrinkWrap` keeps it centred when it does fit.
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(24),
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message.title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message.detail, textAlign: TextAlign.center),
            if (message.needsSignIn && onSignIn != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onSignIn, child: const Text('Sign in')),
            ] else if (message.retryable && onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ],
    );
  }
}
