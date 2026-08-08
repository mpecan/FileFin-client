import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/material.dart';

/// F1: add a server by URL and say clearly what is at that address.
///
/// **The probe is a content-type and payload check, not a status check**, and
/// that decision lives in `filefin_api`'s `probe`. This screen's job is to
/// render its four answers as four different sentences — "reachable", "needs
/// setup", "not FileFin" and "nothing answered" lead to four different next
/// actions, and collapsing any two of them is how a wrong port looks like a
/// wrong product.
class AddServerPage extends StatefulWidget {
  /// Adds a server; calls [onAdded] once one is saved.
  const AddServerPage({required this.onAdded, super.key});

  /// Where the flow goes next — the sign-in screen for the saved server.
  final void Function(SavedServer server) onAdded;

  @override
  State<AddServerPage> createState() => _AddServerPageState();
}

class _AddServerPageState extends State<AddServerPage> {
  final _url = TextEditingController();
  CancelToken? _token;
  bool _busy = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _token?.cancel();
    _url.dispose();
    super.dispose();
  }

  /// True once the typed text parses as an `http://` URL with a host.
  ///
  /// The warning is driven off the parsed scheme rather than a `startsWith`,
  /// so `HTTP://nas.local` warns too — `Uri` lower-cases a scheme and a user
  /// typing capitals is not typing a different protocol.
  bool get _isCleartext {
    final parsed = Uri.tryParse(_url.text.trim());
    return parsed != null && parsed.scheme == 'http' && parsed.host.isNotEmpty;
  }

  Future<void> _probe() async {
    final parsed = Uri.tryParse(_url.text.trim());
    // `Uri.tryParse('nas.local')` succeeds — it is a relative reference with a
    // PATH and no host — so a null check alone is not a validation. Requiring
    // a host and a known scheme is what stops a bare hostname reaching
    // `FileFinClient.forServer` and failing with something about a base URL.
    final usable =
        parsed != null &&
        parsed.host.isNotEmpty &&
        (parsed.isScheme('http') || parsed.isScheme('https'));
    if (!usable) {
      setState(
        () => _problem =
            'Type a full address, including http:// or https:// — for '
            'example http://192.168.1.10:8099',
      );
      return;
    }
    // The origin-as-id rule and the `userInfo` strip both live on `SavedServer`
    // rather than here: they are properties of a saved server, and a screen
    // that reimplemented either would be a second place to get §9 wrong.
    final candidate = SavedServer.fromTypedUrl(parsed);
    final api = FileFinScope.of(context).apiFactory(candidate);
    final token = CancelToken();
    _token = token;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final result = await api.probeServer(cancelToken: token);
      if (!mounted) return;
      switch (result) {
        case FileFinServer():
          FileFinScope.of(context).settings.write(
            FileFinScope.of(context).settings.read().upsert(candidate),
          );
          widget.onAdded(candidate);
        case FileFinServerNeedsSetup():
          setState(
            () => _problem =
                'That is a FileFin server, but its first account has not been '
                'created yet. Finish setup in a browser first — the setup '
                'link is printed by the server itself and never sent over '
                'the API.',
          );
        case NotAFileFinServer(:final reason):
          setState(
            () => _problem =
                'Something answered at that address, but it is not a FileFin '
                'server: $reason',
          );
        case ServerUnreachable(:final cause):
          setState(
            () => _problem =
                'Nothing answered at that address. Check it, and check you are '
                'on the same network as the server. ($cause)',
          );
      }
    } on FileFinApiException catch (error) {
      if (!mounted) return;
      final message = describeApiError(error);
      setState(() => _problem = '${message.title}. ${message.detail}');
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(() => _problem = describeSettingsWriteFailure(error));
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add a server')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _url,
          autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Server address',
            hintText: 'http://192.168.1.10:8099',
            border: OutlineInputBorder(),
          ),
        ),
        if (_isCleartext) ...[
          const SizedBox(height: 12),
          const _CleartextWarning(),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _probe,
          child: Text(_busy ? 'Checking…' : 'Check this address'),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 16),
          Text(
            _problem!,
            key: const Key('add-server-problem'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
  );
}

/// F15's visible flag on plain HTTP, worded for the iOS reality.
///
/// **iOS will not reach a plain-http server outside the local network.**
/// `Info.plist` sets `NSAllowsLocalNetworking` and deliberately not
/// `NSAllowsArbitraryLoads`, which relaxes ATS for local addressing only — so
/// "your password crosses the network in the clear" is only half of what a
/// user needs to know here. Saying both is what stops a public plain-http
/// server looking like a broken app. `docs/verification-backlog.md` carries
/// the device experiment that would confirm the second half.
class _CleartextWarning extends StatelessWidget {
  const _CleartextWarning();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('cleartext-warning'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      'This address is plain HTTP, so your password and everything you watch '
      'cross the network unencrypted. On iPhone and iPad, plain HTTP is only '
      'permitted for servers on your local network.',
      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
    ),
  );
}
