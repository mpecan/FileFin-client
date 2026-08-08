import 'package:filefin_core/filefin_core.dart';
import 'package:meta/meta.dart';

/// One server the user has saved (SPEC.md §7's `servers[]`).
///
/// **No secrets, ever.** `settings.json` is plain JSON in the application
/// support directory — readable by any app on a rooted device — so the session,
/// the password and the certificate pin live in `SecretStore` instead (§9).
/// [lastUser] is here because a cold start needs it to renew a session
/// silently (F2), and a username is not a secret.
///
/// **There is no `wifiOnly` field, and its absence is the decision.** SPEC.md
/// §7 lists one, M4's playback path will read one, and §1 still says a setting
/// nobody reads is a dead branch — the tree already ruled exactly this way on
/// `PlaybackSettings.progressIntervalSecs` (STATE.md). §13 is what makes that
/// cheap: our own formats change freely before release, so M4 adds the field
/// with the code that reads it and no migration is owed to anyone.
///
/// **A `baseUrl` carrying `userInfo` is a credential**, and the constructor
/// refuses one. `https://sam:hunter2@nas.local/` is a thing people type into an
/// address field; M3 shipped it straight to disk and back out as a `Basic`
/// header. [SavedServer.fromTypedUrl] is where a typed URL loses it; this
/// assert is what stops a second construction path from skipping that. It is an
/// assert rather than a repair because a silent repair is a leak nobody ever
/// finds, and rather than a throw because the caller who gets it wrong is us,
/// at test time. **Asserts are off in a release build**, so the guarantee a
/// shipped APK has is the one construction path plus the tests over it — which
/// is why `add_server_page_test` asserts on the bytes that reach the disk.
@immutable
class SavedServer {
  /// A saved server, identified by [id] and reached at [baseUrl].
  SavedServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lastUser = '',
  }) : assert(
         baseUrl.userInfo.isEmpty,
         'A saved baseUrl must not carry userInfo: settings.json is plain '
         'JSON and a user-typed https://user:pass@host is a credential (§9).',
       );

  /// The server a **user typed the address of**, normalised.
  ///
  /// Two normalisations, and both are rules about this type rather than about
  /// whichever screen collected the text:
  ///
  /// - the origin IS the id. It is stable across restarts without a clock or a
  ///   random source, so re-adding the same server updates the saved entry
  ///   rather than creating a second one with its own cookie jar and its own
  ///   certificate pin.
  /// - `userInfo` is dropped. `Uri.origin` already drops it; [baseUrl] is the
  ///   field that used to keep it, and keeping it persisted a password.
  factory SavedServer.fromTypedUrl(Uri url) => SavedServer(
    id: ServerId(url.origin),
    name: url.host,
    baseUrl: url.replace(userInfo: ''),
  );

  /// Decodes one entry. **Deliberately not tolerant** — see [AppSettings].
  factory SavedServer.fromJson(Map<String, Object?> json) => SavedServer(
    id: ServerId(json['id']! as String),
    name: json['name']! as String,
    baseUrl: Uri.parse(json['baseUrl']! as String),
    lastUser: json['lastUser']! as String,
  );

  /// Our own identifier for this server; never sent anywhere.
  final ServerId id;

  /// What the user calls it.
  final String name;

  /// Where it lives.
  final Uri baseUrl;

  /// The account last signed in, for F2's silent renewal. Not a secret.
  final String lastUser;

  /// Encodes one entry.
  Map<String, Object?> toJson() => {
    'id': id.value,
    'name': name,
    'baseUrl': baseUrl.toString(),
    'lastUser': lastUser,
  };

  /// A copy with [lastUser] replaced, written after a successful sign-in.
  SavedServer withLastUser(String user) => SavedServer(
    id: id,
    name: name,
    baseUrl: baseUrl,
    lastUser: user,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedServer &&
      other.id == id &&
      other.name == name &&
      other.baseUrl == baseUrl &&
      other.lastUser == lastUser;

  @override
  int get hashCode => Object.hash(id, name, baseUrl, lastUser);

  /// **No `baseUrl`.** A `toString()` is a log line waiting to happen (§9), and
  /// the id already names which server this is without ever having held
  /// `userInfo`.
  @override
  String toString() => 'SavedServer(${id.value}, $name)';
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
