import 'package:flutter/material.dart';

/// What a first launch shows: there is no saved server yet (F1's landing).
///
/// An empty state rather than a spinner, and the distinction is the point.
/// "Nothing here" and "still loading" look identical if you show a spinner for
/// both, and a first launch has nothing to wait for — the wait would be a lie
/// about work that is not happening.
class NoServerPage extends StatelessWidget {
  /// Builds the empty state.
  const NoServerPage({super.key});

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
              'No server yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Add the address of your FileFin server to browse its library.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
