import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/certificate_prompt.dart';
import 'package:filefin_mobile/src/servers/server_api.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/material.dart';

/// Sign in to one saved server.
///
/// **This screen is reached deliberately, never by a 401.** A 401 on any call
/// is routine and `filefin_api` already re-authenticates and
/// retries once; only a `SessionExpired` — which means that retry also
/// failed — routes here. A UI-level 401 handler is the tempting bug, and it
/// would prompt for a password every time a server restarted mid-scroll.
class SignInPage extends StatefulWidget {
  /// Signs in to [server], calling [onSignedIn] with the API on success.
  const SignInPage({
    required this.server,
    required this.onSignedIn,
    super.key,
  });

  /// Which saved server this signs in to.
  final SavedServer server;

  /// Where the flow goes next, with the signed-in API.
  final void Function(SavedServer server, LibraryApi api) onSignedIn;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  late final TextEditingController _user = TextEditingController(
    text: widget.server.lastUser,
  );
  final _password = TextEditingController();
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Sign-in, with the accept-and-pin loop around it.
  ///
  /// **Exactly two attempts, written out.** A retry expressed as recursion —
  /// or as a loop whose bound is a condition — is the shape CLAUDE.md names as
  /// a mutation-gate hang: rewrite the condition and the recursion is
  /// unbounded, `mutation_test` times the run out at 300 s and reports the
  /// mutant as *undetected*. Two statements cannot be rewritten into a loop.
  Future<void> _signIn() async {
    final untrusted = await _attempt();
    if (untrusted == null || !mounted) return;
    if (!await promptToTrust(context, untrusted)) {
      // Declining is a decision, not an error to retry. The panel says what
      // was refused and why, and nothing is stored.
      if (mounted) setState(() => _problem = _describe(untrusted));
      return;
    }
    if (!mounted) return;
    // The pin is integrity data and belongs in the secure store rather than in
    // `settings.json`, which is a plain file any app on a rooted device can
    // edit. Writing it is what makes the NEXT
    // client — built by `apiForServer` below — carry it.
    await FileFinScope.of(context).secrets.write(
      widget.server.id,
      SecretKind.certificatePin,
      untrusted.fingerprint,
    );
    final again = await _attempt();
    if (again != null && mounted) {
      setState(() => _problem = _describe(again));
    }
  }

  String _describe(FileFinApiException error) {
    final message = describeApiError(error);
    return '${message.title}. ${message.detail}';
  }

  /// One attempt. Returns the untrusted certificate when that is what stopped
  /// it, and null for every other outcome — success included.
  Future<CertificateNotTrusted?> _attempt() async {
    final deps = FileFinScope.of(context);
    final api = await apiForServer(deps, widget.server);
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await api.login(
        Credentials(username: _user.text.trim(), password: _password.text),
      );
      // The username is not a secret and a cold start needs it to renew a
      // session silently. The password never comes near this file's
      // storage — `filefin_api` puts it in the SecretStore.
      //
      // The SELECTION is written here too, and this is the only place that
      // writes it once's picker: signing in is what makes a server the
      // one a launch should open, and a saved server nobody ever signed in to
      // is not it.
      deps.settings.write(
        deps.settings
            .read()
            .upsert(widget.server.withLastUser(_user.text.trim()))
            .withSelected(widget.server.id),
      );
      if (!mounted) {
        api.close();
        return null;
      }
      widget.onSignedIn(widget.server, api);
      return null;
      // the trust prompt, and the ONLY exception this screen hands back rather
      // than renders: it is a question for the user, not a failure to report.
    } on CertificateNotTrusted catch (error) {
      api.close();
      return error;
    } on FileFinApiException catch (error) {
      api.close();
      if (!mounted) return null;
      setState(() => _problem = _describe(error));
      return null;
    } on FileSystemException catch (error) {
      api.close();
      if (!mounted) return null;
      setState(() => _problem = describeSettingsWriteFailure(error));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Sign in to ${widget.server.name}')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _user,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: true,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _busy ? null : _signIn(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: Text(_busy ? 'Signing in…' : 'Sign in'),
        ),
        if (_problem != null) ...[
          const SizedBox(height: 16),
          Text(
            _problem!,
            key: const Key('sign-in-problem'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
  );
}
