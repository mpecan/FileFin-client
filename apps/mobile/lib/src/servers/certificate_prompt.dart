import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:flutter/material.dart';

/// F15's trust-on-first-use prompt: the fingerprint, and a deliberate accept.
///
/// **Returns false unless the user actually said yes.** A dismissed dialog is
/// a `null` result and must not be read as acceptance — trust-on-first-use is
/// only defensible when the first use is a decision somebody took.
///
/// There is deliberately **no equivalent for a CHANGED certificate** (D19):
/// offering an accept button there would be the silent re-accept F15 forbids,
/// implemented by hand.
Future<bool> promptToTrust(
  BuildContext context,
  CertificateNotTrusted error,
) async {
  final message = describeApiError(error);
  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('certificate-prompt'),
      title: Text(message.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.detail),
            const SizedBox(height: 12),
            // The fingerprint again, on its own and selectable, because the
            // one job this screen has is letting somebody compare it against
            // what `openssl x509 -fingerprint -sha256` printed on their
            // server. Buried in a paragraph it is decoration.
            SelectableText(
              error.fingerprint,
              key: const Key('certificate-fingerprint'),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Trust this server'),
        ),
      ],
    ),
  );
  return accepted ?? false;
}
