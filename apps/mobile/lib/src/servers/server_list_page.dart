import 'dart:io';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/errors/error_presentation.dart';
import 'package:filefin_mobile/src/scope.dart';
import 'package:filefin_mobile/src/servers/server_api.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:filefin_mobile/src/servers/settings_store.dart';
import 'package:flutter/material.dart';

/// F11's picker: the saved servers, which one a launch opens, and removal.
///
/// **The mechanism has existed since M2 and had no way in.**
/// `FileFinClient.forServer` gives every `ServerId` its own cookie jar, secret
/// namespace and certificate pinner, `AppSettings.servers` is a list and
/// `upsert` is id-keyed — and until M7.4 the app held exactly one client and
/// `app.dart` named the gap in its own comment. This screen is the way in.
///
/// **It reads `settings.json` on every build rather than caching a list**, and
/// that is deliberate: the file is the truth, a removal changes it, and a
/// cached copy is one more thing that can disagree with what a launch will
/// actually do. This is a settings screen — it is built a handful of times, not
/// once per frame of a scroll.
///
/// Switching and signing out are **not** done here. Closing the previous client
/// is `HomeRoute`'s job and there is exactly one method that does it, because a
/// second place to swap clients is a second place to leak a socket.
class ServerListPage extends StatefulWidget {
  /// Lists the saved servers, marking [selected].
  const ServerListPage({
    required this.selected,
    required this.onSelect,
    required this.onRemoved,
    required this.onAdd,
    super.key,
  });

  /// The server a launch currently opens, or null before the first sign-in.
  final ServerId? selected;

  /// Asks for the tapped server to become the current one.
  final void Function(SavedServer server) onSelect;

  /// Reports a server that has just been forgotten, so the shell can drop
  /// its client if that is the one it was showing.
  final void Function(SavedServer server) onRemoved;

  /// Starts F1's add-a-server flow.
  final VoidCallback onAdd;

  @override
  State<ServerListPage> createState() => _ServerListPageState();
}

class _ServerListPageState extends State<ServerListPage> {
  String? _problem;

  /// Forgets [server] completely: the session on the server, then its three
  /// secrets, then its settings entry.
  ///
  /// **The secrets go first, and the order is the §9 decision.** If the
  /// settings write then fails, the entry survives with no credentials — the
  /// next sign-in prompts, which is an inconvenience. The other order leaves a
  /// password in the Keychain for a server no screen can reach, keyed by an id
  /// nothing holds any more, with nothing left that could ever delete it.
  /// Losing a credential is the safe direction.
  ///
  /// **`widget.onRemoved` is called whether or not THIS screen survived the
  /// awaits above, and that is the fix rather than an oversight.** There are
  /// four real `await`s in front of the write; pop the picker during them and
  /// the write still committed while the shell never heard about it, so the
  /// app went on browsing a server `settings.json` no longer holds — and
  /// `SignInPage` `upsert`s it straight back at the next sign-in, which is a
  /// removed server reappearing. The guard belongs on `setState`, which is
  /// about this widget, not on the callback, which is about the shell's.
  Future<void> _remove(AppDependencies deps, SavedServer server) async {
    final unanswered = await _endSession(deps, server);
    for (final kind in SecretKind.values) {
      await deps.secrets.delete(server.id, kind);
    }
    try {
      deps.settings.write(deps.settings.read().remove(server.id));
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _problem = describeSettingsWriteFailure(error));
      }
      return;
    }
    widget.onRemoved(server);
    if (mounted) setState(() => _problem = unanswered);
  }

  /// Ends the session on the server while the cookie that proves it still
  /// exists, and answers with what to say when it could not be reached.
  ///
  /// **Removal used to leave the session alive with nothing left to end it.**
  /// `logout()` needs the session secret this method is about to delete, so it
  /// has to happen first or not at all — and "not at all" means a server that
  /// keeps a live session for an account the phone has forgotten, which is
  /// precisely what F2's sign-out exists to prevent.
  ///
  /// A server that does not answer is not a reason to refuse the removal:
  /// `SessionManager.logout`'s `finally` has already cleared the jar and both
  /// secrets by the time it throws, and someone whose NAS is unplugged must
  /// still be able to forget it.
  Future<String?> _endSession(AppDependencies deps, SavedServer server) async {
    final api = await apiForServer(deps, server);
    try {
      await api.logout();
      return null;
    } on FileFinApiException catch (error) {
      // Returned rather than shown here, because [_remove] ends by setting
      // `_problem` and would otherwise clear it a moment later.
      return '${describeApiError(error).title}. This server was removed '
          'anyway; its session there may outlive it.';
    } finally {
      api.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final deps = FileFinScope.of(context);
    final servers = deps.settings.read().servers;
    return Scaffold(
      appBar: AppBar(title: const Text('Servers')),
      body: ListView(
        children: [
          if (servers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No servers saved', textAlign: TextAlign.center),
            ),
          for (final server in servers)
            ListTile(
              // The ADDRESS as well as the name: two servers a user called
              // "NAS" are told apart by nothing else, and switching to the
              // wrong one is invisible until a library loads.
              title: Text(server.name),
              subtitle: Text(server.baseUrl.toString()),
              leading: Icon(
                server.id == widget.selected ? Icons.check : Icons.dns_outlined,
              ),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(deps, server),
              ),
              onTap: () => widget.onSelect(server),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton(
              onPressed: widget.onAdd,
              child: const Text('Add a server'),
            ),
          ),
          if (_problem != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _problem!,
                key: const Key('server-list-problem'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
