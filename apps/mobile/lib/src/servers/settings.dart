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
/// [wifiOnly] and [allowUnverifiedPlayback] are both **per server**, and both
/// arrived at M4 with the code that reads them — §1's rule, and §13 is what
/// made waiting free.
///
/// [allowUnverifiedPlayback] is D10. libmpv opens its own socket from native
/// code and verifies no certificate by default (measured: mpv 0.41.0 accepted
/// this repository's own self-signed certificate and logged the request;
/// `--tls-verify=yes` refused it with `error:0A000086` and logged nothing), so
/// F15's pin does not reach playback at all. The default is `false` — refuse —
/// because the alternative is handing the session cookie to a peer whose
/// certificate nothing checked. Turning it on is a per-server decision with a
/// **persistent banner** attached, because what is given up is ongoing.
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
    wifiOnly: json['wifiOnly']! as bool,
    allowUnverifiedPlayback: json['allowUnverifiedPlayback']! as bool,
  );

  /// Our own identifier for this server; never sent anywhere.
  final ServerId id;

  /// What the user calls it.
  final String name;

  /// Where it lives.
  final Uri baseUrl;

  /// The account last signed in, for F2's silent renewal. Not a secret.
  final String lastUser;

  /// F13's hard refusal: never play over a metered connection at all.
  final bool wifiOnly;

  /// D10: play anyway when only F15's pin vouches for the certificate.
  final bool allowUnverifiedPlayback;

  /// Encodes one entry.
  Map<String, Object?> toJson() => {
    'id': id.value,
    'name': name,
    'baseUrl': baseUrl.toString(),
    'lastUser': lastUser,
    'wifiOnly': wifiOnly,
    'allowUnverifiedPlayback': allowUnverifiedPlayback,
  };

  /// A copy with [lastUser] replaced, written after a successful sign-in.
  SavedServer withLastUser(String user) => copyWith(lastUser: user);

  /// A copy with the playback settings a user changed.
  ///
  /// One method rather than three, because every caller writes the whole entry
  /// back through [AppSettings.upsert] and three near-identical copies is what
  /// `just dupes` exists to notice.
  SavedServer copyWith({
    String? lastUser,
    bool? wifiOnly,
    bool? allowUnverifiedPlayback,
  }) => SavedServer(
    id: id,
    name: name,
    baseUrl: baseUrl,
    lastUser: lastUser ?? this.lastUser,
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
      other.wifiOnly == wifiOnly &&
      other.allowUnverifiedPlayback == allowUnverifiedPlayback;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    baseUrl,
    lastUser,
    wifiOnly,
    allowUnverifiedPlayback,
  );

  /// **No `baseUrl`.** A `toString()` is a log line waiting to happen (§9), and
  /// the id already names which server this is without ever having held
  /// `userInfo`.
  @override
  String toString() => 'SavedServer(${id.value}, $name)';
}

/// SPEC.md §7's `playback { … }` block — the settings that are not per server.
///
/// **Adding this block discards every `settings.json` an earlier build wrote**,
/// and that is §13 working as designed rather than an accident: the decoder is
/// strict, a file with no `playback` key fails it, and `SettingsStore` turns a
/// failed decode into [AppSettings.empty]. Nothing has shipped, so there are no
/// installs to migrate — but it does happen to a developer with a saved server,
/// which is why it is written down here and in STATE.md instead of being
/// discovered.
///
/// [meteredWarnBytes] defaults to 500 MB: a few minutes of a high-bitrate
/// stream, and well under a typical monthly allowance, so the prompt means
/// something without firing on every television episode.
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
  /// seconds. 30 is upstream's own (`web/src/views/library/Player.svelte`).
  final int progressIntervalSecs;

  /// The size above which a metered attempt asks first (F13).
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
  const AppSettings({
    this.servers = const [],
    this.playback = const PlaybackPrefs(),
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
  );

  /// No servers saved yet: a first launch, or a file we could not read.
  static const empty = AppSettings();

  /// The saved servers, in the order they were added.
  final List<SavedServer> servers;

  /// The settings that are not per server (SPEC.md §7).
  final PlaybackPrefs playback;

  /// Encodes the whole file.
  Map<String, Object?> toJson() => {
    'servers': [for (final server in servers) server.toJson()],
    'playback': playback.toJson(),
  };

  /// A copy with [server] added, or replacing an entry with the same id.
  AppSettings upsert(SavedServer server) => AppSettings(
    servers: [
      for (final existing in servers)
        if (existing.id == server.id) server else existing,
      if (!servers.any((e) => e.id == server.id)) server,
    ],
    playback: playback,
  );

  /// A copy with the playback block replaced.
  AppSettings withPlayback(PlaybackPrefs prefs) =>
      AppSettings(servers: servers, playback: prefs);

  @override
  String toString() => 'AppSettings(${servers.length} server(s), $playback)';
}
