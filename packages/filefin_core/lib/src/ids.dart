/// The identifiers the server addresses things by.
///
/// They wrap **different** primitives — a `MediaId` is a 12-char hex string
///, a `CategoryId` is an `int64` — so once
/// either decays to its representation the compiler can no longer catch a
/// mix-up, and the server answers a wrong one with a 404 rather than an
/// explanation.
///
/// Every one is declared `implements Object`, never `implements String` or
/// `implements int`. `implements <the representation>` forwards assignability
/// to the primitive, which would let a bare `String` be passed where a
/// `MediaId` is expected and defeat the entire rule.
library;

/// A media item id: 12 hex characters, `sha1(category + "/" + folder)[:12]`.
extension type const MediaId(String value) implements Object {}

/// A category id. `0` is the top-level parent sentinel, not "absent".
extension type const CategoryId(int value) implements Object {}

/// A 0-based index into a media item's `files[]`; the `{n}` in playback paths.
extension type const FileIndex(int value) implements Object {}

/// A 0-based index into a file's `subtitles[]`; the `{k}` in the subtitle path.
extension type const SubtitleIndex(int value) implements Object {}

/// **Our own** identifier for a saved server. It is never sent to any server.
///
/// The other four name things the server named. This one names a row in the
/// client's own server list, and keys the three per-server
/// things `filefin_api` holds apart: the cookie jar, the secret-store
/// namespace (`filefin/{serverId}/session|password|certpin`) and the accepted
/// fingerprint. Two servers sharing a jar would send one's session cookie to
/// the other; two sharing a pin would defeat pinning.
///
/// It carries no `JsonConverter`, unlike the four above: it appears in no
/// payload in either direction, so one would be a dead branch.
extension type const ServerId(String value) implements Object {}
