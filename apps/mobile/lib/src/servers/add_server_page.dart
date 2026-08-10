import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/certificate_prompt.dart';
import 'package:filefin_mobile/src/servers/server_api.dart';
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
    final untrusted = await _check(candidate);
    if (untrusted == null || !mounted) return;
    if (!await promptToTrust(context, untrusted)) {
      if (mounted) setState(() => _problem = _describe(untrusted));
      return;
    }
    if (!mounted) return;
    // Captured before the second probe, because a successful one navigates
    // away and `context` stops being usable — and the cleanup below has to
    // happen on both outcomes.
    final deps = FileFinScope.of(context);
    await deps.secrets.write(
      candidate.id,
      SecretKind.certificatePin,
      untrusted.fingerprint,
    );
    // EXACTLY one more, for the reason `SignInPage._signIn` records: a bounded
    // retry written as two statements cannot be rewritten into a loop.
    final again = await _check(candidate);
    if (again != null && mounted) {
      setState(() => _problem = _describe(again));
    }
    await _forgetOrphanedPin(deps, candidate);
  }

  /// Drops the pin again when the address it was accepted for was not saved.
  ///
  /// **The pin is written BEFORE the second probe decides whether this is a
  /// FileFin server at all**, and it has to be: `apiForServer` reads it out of
  /// the store to build the client that probe runs on. So a refusal — "not a
  /// FileFin server", "needs setup", a typo in the port — left a
  /// `SecretKind.certificatePin` keyed to an origin that appears in no
  /// settings file, and `ServerListPage._remove` is the only deleter there is
  /// and it iterates saved servers.
  ///
  /// It is worse than untidiness. The id IS the origin, so adding that same
  /// address later silently loads the orphan and the server connects pinned
  /// without ever asking — which is F15's deliberate accept skipped entirely,
  /// for a certificate the user was shown once and did not go on to use.
  Future<void> _forgetOrphanedPin(
    AppDependencies deps,
    SavedServer candidate,
  ) async {
    final saved = deps.settings.read().servers.any((e) => e.id == candidate.id);
    if (saved) return;
    await deps.secrets.delete(candidate.id, SecretKind.certificatePin);
  }

  String _describe(FileFinApiException error) {
    final message = describeApiError(error);
    return '${message.title}. ${message.detail}';
  }

  /// One probe. Returns the untrusted certificate when that is what stopped it.
  Future<CertificateNotTrusted?> _check(SavedServer candidate) async {
    final api = await apiForServer(FileFinScope.of(context), candidate);
    final token = CancelToken();
    _token = token;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final result = await api.probeServer(cancelToken: token);
      if (!mounted) return null;
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
      // F15's prompt: a question for the user rather than a verdict about
      // what is at this address. Until M7.5 the probe swallowed it into
      // `ServerUnreachable` and this screen said "Nothing answered at that
      // address" about a server that had answered.
    } on CertificateNotTrusted catch (error) {
      return error;
    } on FileFinApiException catch (error) {
      if (!mounted) return null;
      setState(() => _problem = _describe(error));
    } on FileSystemException catch (error) {
      if (!mounted) return null;
      setState(() => _problem = describeSettingsWriteFailure(error));
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
    return null;
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
