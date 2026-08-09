import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/material.dart';

/// F2: sign in to one saved server.
///
/// **This screen is reached deliberately, never by a 401.** A 401 on any call
/// is routine (SPEC.md L1) and `filefin_api` already re-authenticates and
/// retries once (F3); only a `SessionExpired` — which means that retry also
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

  Future<void> _signIn() async {
    final deps = FileFinScope.of(context);
    final api = deps.apiFactory(widget.server);
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await api.login(
        Credentials(username: _user.text.trim(), password: _password.text),
      );
      // The username is not a secret and a cold start needs it to renew a
      // session silently (F2). The password never comes near this file's
      // storage — `filefin_api` puts it in the SecretStore.
      //
      // The SELECTION is written here too, and this is the only place that
      // writes it until M7.4's picker: signing in is what makes a server the
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
        return;
      }
      widget.onSignedIn(widget.server, api);
    } on FileFinApiException catch (error) {
      api.close();
      if (!mounted) return;
      final message = describeApiError(error);
      setState(() => _problem = '${message.title}. ${message.detail}');
    } on FileSystemException catch (error) {
      api.close();
      if (!mounted) return;
      setState(() => _problem = describeSettingsWriteFailure(error));
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
