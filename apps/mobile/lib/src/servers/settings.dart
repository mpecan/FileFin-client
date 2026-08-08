import 'package:filefin_core/filefin_core.dart';
import 'package:meta/meta.dart';

/// One server the user has saved (SPEC.md §7's `servers[]`).
///
/// **No secrets, ever.** `settings.json` is plain JSON in the application
/// support directory — readable by any app on a rooted device — so the session,
/// the password and the certificate pin live in `SecretStore` instead (§9).
/// [lastUser] is here because a cold start needs it to renew a session
/// silently (F2), and a username is not a secret.
@immutable
class SavedServer {
  /// A saved server, identified by [id] and reached at [baseUrl].
  const SavedServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lastUser = '',
    this.wifiOnly = false,
  });

  /// Decodes one entry. **Deliberately not tolerant** — see [AppSettings].
  factory SavedServer.fromJson(Map<String, Object?> json) => SavedServer(
    id: ServerId(json['id']! as String),
    name: json['name']! as String,
    baseUrl: Uri.parse(json['baseUrl']! as String),
    lastUser: json['lastUser']! as String,
    wifiOnly: json['wifiOnly']! as bool,
  );

  /// Our own identifier for this server; never sent anywhere.
  final ServerId id;

  /// What the user calls it.
  final String name;

  /// Where it lives.
  final Uri baseUrl;

  /// The account last signed in, for F2's silent renewal. Not a secret.
  final String lastUser;

  /// F13's per-server metered guard. Read by M4's playback path.
  final bool wifiOnly;

  /// Encodes one entry.
  Map<String, Object?> toJson() => {
    'id': id.value,
    'name': name,
    'baseUrl': baseUrl.toString(),
    'lastUser': lastUser,
    'wifiOnly': wifiOnly,
  };

  /// A copy with [lastUser] replaced, written after a successful sign-in.
  SavedServer withLastUser(String user) => SavedServer(
    id: id,
    name: name,
    baseUrl: baseUrl,
    lastUser: user,
    wifiOnly: wifiOnly,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedServer &&
      other.id == id &&
      other.name == name &&
      other.baseUrl == baseUrl &&
      other.lastUser == lastUser &&
      other.wifiOnly == wifiOnly;

  @override
  int get hashCode => Object.hash(id, name, baseUrl, lastUser, wifiOnly);

  @override
  String toString() => 'SavedServer(${id.value}, $name, $baseUrl)';
}

/// Everything `settings.json` holds.
///
/// **The decoder is strict on purpose, and this comment exists so nobody
/// "fixes" it.** §8's tolerance rule governs the *server's* formats, where we
/// are the ones who must cope with a field appearing. This is **our own**
/// format, and §13 says our own formats change freely before release: no
/// migration, no lenient decoder, no fallback branch reading what an earlier
/// build wrote. A missing key here means the file was written by a build that
/// no longer exists, and the right answer is to start over rather than to
/// half-read it.
///
/// `SettingsStore` is what turns a strict decode failure into an empty
/// settings object, so the strictness costs a user nothing.
@immutable
class AppSettings {
  /// The settings, or [AppSettings.empty] when there is no file.
  const AppSettings({this.servers = const []});

  /// Decodes the whole file. Throws on anything unexpected — see the class doc.
  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    servers: [
      for (final entry in json['servers']! as List<Object?>)
        SavedServer.fromJson(entry! as Map<String, Object?>),
    ],
  );

  /// No servers saved yet: a first launch, or a file we could not read.
  static const empty = AppSettings();

  /// The saved servers, in the order they were added.
  final List<SavedServer> servers;

  /// Encodes the whole file.
  Map<String, Object?> toJson() => {
    'servers': [for (final server in servers) server.toJson()],
  };

  /// A copy with [server] added, or replacing an entry with the same id.
  AppSettings upsert(SavedServer server) => AppSettings(
    servers: [
      for (final existing in servers)
        if (existing.id == server.id) server else existing,
      if (!servers.any((e) => e.id == server.id)) server,
    ],
  );

  @override
  String toString() => 'AppSettings(${servers.length} server(s))';
}
