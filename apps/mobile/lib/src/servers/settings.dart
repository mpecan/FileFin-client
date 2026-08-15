import 'package:filefin_core/filefin_core.dart';
import 'package:meta/meta.dart';

/// How a saved server is signed into. Not a secret — it says which kind of
/// credential to ask for, never the credential itself.
enum AuthMode {
  /// Username and password, with a silently renewed session.
  password,

  /// A personal access token, pasted from the server's own Settings page.
  token,
}

/// One server the user has saved.
///
/// **No secrets, ever**: `settings.json` is plain JSON any app on a rooted
/// device can read. [lastUser] is here because a silent renewal needs it,
/// [authMode] so a cold start builds the right client without asking, and
/// [wifiOnly]/[allowUnverifiedPlayback] are both per server.
///
/// **A `baseUrl` carrying `userInfo` is a credential**, and the constructor
/// refuses one: letting it through writes a password to disk and sends it
/// back out as a `Basic` header. [SavedServer.fromTypedUrl] is where a typed
/// URL loses it, and the assert stops a second path skipping that. Asserts
/// are off in release, so the shipped guarantee is that path plus its test.
@immutable
class SavedServer {
  /// A saved server, identified by [id] and reached at [baseUrl].
  SavedServer({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lastUser = '',
    this.authMode = AuthMode.password,
    this.wifiOnly = false,
    this.allowUnverifiedPlayback = false,
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
  ///  random source, so re-adding the same server updates the saved entry
  ///  rather than creating a second one with its own cookie jar and its own
  ///  certificate pin.
  /// - `userInfo` is dropped. `Uri.origin` already drops it; [baseUrl] is the
  ///   field that carries it, and persisting it would persist a password.
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
    authMode: AuthMode.values.byName(json['authMode']! as String),
    wifiOnly: json['wifiOnly']! as bool,
    allowUnverifiedPlayback: json['allowUnverifiedPlayback']! as bool,
  );

  /// Our own identifier for this server; never sent anywhere.
  final ServerId id;

  /// What the user calls it.
  final String name;

  /// Where it lives.
  final Uri baseUrl;

  /// The account last signed in, for a silent renewal. Not a secret. Only
  /// meaningful for [AuthMode.password] — a token has no separate account
  /// name this client ever asks for.
  final String lastUser;

  /// The credential kind the last successful sign-in used.
  final AuthMode authMode;

  /// The hard refusal: never play over a metered connection at all.
  final bool wifiOnly;

  /// Play anyway when only the certificate
  /// pin vouches for the certificate.
  final bool allowUnverifiedPlayback;

  /// Encodes one entry.
  Map<String, Object?> toJson() => {
    'id': id.value,
    'name': name,
    'baseUrl': baseUrl.toString(),
    'lastUser': lastUser,
    'authMode': authMode.name,
    'wifiOnly': wifiOnly,
    'allowUnverifiedPlayback': allowUnverifiedPlayback,
  };

  /// A copy with [lastUser] replaced, written after a successful password
  /// sign-in.
  SavedServer withLastUser(String user) =>
      copyWith(lastUser: user, authMode: AuthMode.password);

  /// A copy with [AuthMode.token] recorded, written after a successful token
  /// sign-in.
  ///
  /// [lastUser] is cleared rather than left stale: it would otherwise keep
  /// showing an account name from a password sign-in that may not even be
  /// the one the token belongs to.
  SavedServer withTokenAuth() =>
      copyWith(lastUser: '', authMode: AuthMode.token);

  /// A copy with the playback settings a user changed.
  ///
  /// One method rather than three, because every caller writes the whole entry
  /// back through [AppSettings.upsert] and three near-identical copies is what
  /// `just dupes` exists to notice.
  SavedServer copyWith({
    String? lastUser,
    AuthMode? authMode,
    bool? wifiOnly,
    bool? allowUnverifiedPlayback,
  }) => SavedServer(
    id: id,
    name: name,
    baseUrl: baseUrl,
    lastUser: lastUser ?? this.lastUser,
    authMode: authMode ?? this.authMode,
    wifiOnly: wifiOnly ?? this.wifiOnly,
    allowUnverifiedPlayback:
        allowUnverifiedPlayback ?? this.allowUnverifiedPlayback,
  );

  @override
  bool operator ==(Object other) =>
      other is SavedServer &&
      other.id == id &&
      other.name == name &&
      other.baseUrl == baseUrl &&
      other.lastUser == lastUser &&
      other.authMode == authMode &&
      other.wifiOnly == wifiOnly &&
      other.allowUnverifiedPlayback == allowUnverifiedPlayback;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    baseUrl,
    lastUser,
    authMode,
    wifiOnly,
    allowUnverifiedPlayback,
  );

  /// **No `baseUrl`.** A `toString()` is a log line waiting to happen, and
  /// the id already names which server this is without ever having held
  /// `userInfo`.
  @override
  String toString() => 'SavedServer(${id.value}, $name)';
}

/// The `playback { … }` block — the settings that are not per server.
///
/// **Adding this block discarded every `settings.json` an earlier build
/// wrote** — working as designed: the decoder is strict and a failed decode
/// becomes [AppSettings.empty]. Nothing has shipped, but it does happen to a
/// developer with a saved server.
///
/// [meteredWarnBytes] defaults to 500 MB: a few minutes of high-bitrate stream
/// and well under a monthly allowance, so the prompt means something without
/// firing on every television episode.
@immutable
class PlaybackPrefs {
  /// The playback settings, at their defaults unless a user changed them.
  const PlaybackPrefs({
    this.progressIntervalSecs = 30,
    this.meteredWarnBytes = 500 * 1000 * 1000,
  });

  /// Decodes the block. Throws on anything unexpected — see [AppSettings].
  factory PlaybackPrefs.fromJson(Map<String, Object?> json) => PlaybackPrefs(
    progressIntervalSecs: json['progressIntervalSecs']! as int,
    meteredWarnBytes: json['meteredWarnBytes']! as int,
  );

  /// How far playback must move before a checkpoint is reported, in **media**
  /// seconds. 30 is upstream's own.
  final int progressIntervalSecs;

  /// The size above which a metered attempt asks first.
  final int meteredWarnBytes;

  /// Encodes the block.
  Map<String, Object?> toJson() => {
    'progressIntervalSecs': progressIntervalSecs,
    'meteredWarnBytes': meteredWarnBytes,
  };

  /// A copy with whichever field the settings sheet changed.
  PlaybackPrefs copyWith({int? progressIntervalSecs, int? meteredWarnBytes}) =>
      PlaybackPrefs(
        progressIntervalSecs: progressIntervalSecs ?? this.progressIntervalSecs,
        meteredWarnBytes: meteredWarnBytes ?? this.meteredWarnBytes,
      );

  @override
  bool operator ==(Object other) =>
      other is PlaybackPrefs &&
      other.progressIntervalSecs == progressIntervalSecs &&
      other.meteredWarnBytes == meteredWarnBytes;

  @override
  int get hashCode => Object.hash(progressIntervalSecs, meteredWarnBytes);

  @override
  String toString() =>
      'PlaybackPrefs(every ${progressIntervalSecs}s, warn above '
      '$meteredWarnBytes bytes)';
}

/// Everything `settings.json` holds.
///
/// **The decoder is strict on purpose, and this comment exists so nobody
/// "fixes" it.** Tolerance governs the *server's* formats; this is our own,
/// and ours change freely before release — no migration, no
/// lenient decoder. A missing key means an obsolete build wrote
/// the file, and the right answer is to start over rather than half-read it.
/// `SettingsStore` turns the failure into empty settings, so it costs a user
/// nothing.
@immutable
class AppSettings {
  /// The settings, or [AppSettings.empty] when there is no file.
  const AppSettings({
    this.servers = const [],
    this.playback = const PlaybackPrefs(),
    this.selectedServerId,
  });

  /// Decodes the whole file. Throws on anything unexpected — see the class doc.
  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    servers: [
      for (final entry in json['servers']! as List<Object?>)
        SavedServer.fromJson(entry! as Map<String, Object?>),
    ],
    playback: PlaybackPrefs.fromJson(
      json['playback']! as Map<String, Object?>,
    ),
    selectedServerId: _decodeSelected(json),
  );

  /// Reads `selectedServerId`, whose VALUE is nullable but whose KEY is not.
  ///
  /// `json['selectedServerId'] as String?` would have read a file written
  /// read as "nothing selected" and carried on, which is the lenient decoder
  /// we do not write for our own formats: a file an older build wrote is
  /// replaced, not half-read. Requiring the key is what makes that happen, and
  /// `SettingsStore.read` turns the refusal into empty settings.
  static ServerId? _decodeSelected(Map<String, Object?> json) {
    if (!json.containsKey('selectedServerId')) {
      throw const FormatException(
        'settings.json has no selectedServerId key, so it was written by a '
        'build that no longer exists',
      );
    }
    final value = json['selectedServerId'];
    return value == null ? null : ServerId(value as String);
  }

  /// No servers saved yet: a first launch, or a file we could not read.
  static const empty = AppSettings();

  /// The saved servers, in the order they were added.
  final List<SavedServer> servers;

  /// The settings that are not per server.
  final PlaybackPrefs playback;

  /// Which saved server a launch should open, or null before the first
  /// sign-in.
  ///
  /// The id rather than an index, because `servers` is reordered by nothing
  /// today and by removal tomorrow, and an index would silently select a
  /// different server the first time one is deleted.
  final ServerId? selectedServerId;

  /// The server a launch should try, or null when nothing is saved.
  ///
  /// Falls back to the first saved server when [selectedServerId] is null or
  /// names one that is gone. That fallback is not a stand-in for a picker —
  /// The server picker is what writes the selection — it is what stops a
  /// removed
  /// server stranding every later launch on an empty screen.
  SavedServer? get selectedServer {
    for (final server in servers) {
      if (server.id == selectedServerId) return server;
    }
    return servers.isEmpty ? null : servers.first;
  }

  /// Encodes the whole file.
  Map<String, Object?> toJson() => {
    'servers': [for (final server in servers) server.toJson()],
    'playback': playback.toJson(),
    'selectedServerId': selectedServerId?.value,
  };

  /// A copy with [server] added, or replacing an entry with the same id.
  AppSettings upsert(SavedServer server) => AppSettings(
    servers: [
      for (final existing in servers)
        if (existing.id == server.id) server else existing,
      if (!servers.any((e) => e.id == server.id)) server,
    ],
    playback: playback,
    selectedServerId: selectedServerId,
  );

  /// A copy with [server] gone, and the selection cleared if it named it.
  ///
  /// **Clearing the selection is not tidying.** [selectedServer]'s fallback
  /// already stops a dangling id stranding a launch, so leaving it would look
  /// harmless — until the user re-adds a server at the same address. The id is
  /// the origin (see [SavedServer.fromTypedUrl]), so the stale selection would
  /// match again and the server they removed would silently become the one
  /// every launch opens.
  AppSettings remove(ServerId server) => AppSettings(
    servers: [
      for (final existing in servers)
        if (existing.id != server) existing,
    ],
    playback: playback,
    selectedServerId: selectedServerId == server ? null : selectedServerId,
  );

  /// A copy with the playback block replaced.
  AppSettings withPlayback(PlaybackPrefs prefs) => AppSettings(
    servers: servers,
    playback: prefs,
    selectedServerId: selectedServerId,
  );

  /// A copy with [server] selected — written when a sign-in succeeds.
  AppSettings withSelected(ServerId server) => AppSettings(
    servers: servers,
    playback: playback,
    selectedServerId: server,
  );

  @override
  String toString() =>
      'AppSettings(${servers.length} server(s), $playback, '
      'selected ${selectedServerId?.value ?? 'none'})';
}
