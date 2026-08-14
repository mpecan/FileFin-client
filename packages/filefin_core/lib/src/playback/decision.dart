import 'package:filefin_core/src/models/media_detail.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'decision.freezed.dart';

/// The connection a playback attempt would use.
enum NetworkType {
  /// Unmetered: Wi-Fi or Ethernet. Neither guard below applies.
  wifi,

  /// Metered — cellular, or **any connection we cannot show to be unmetered**.
  ///
  /// The wording is deliberate and it is a correction. `connectivity_plus`
  /// reports a transport, not a cost: its result set is
  /// `{wifi, ethernet, mobile, vpn, bluetooth, satellite, other, none}` with no
  /// metered flag on either platform. So a phone hotspot the OS itself
  /// considers metered arrives as `wifi` and this guard never fires — which is
  /// exactly the case F13 exists for. `docs/verification-backlog.md` row 20
  /// carries the device experiment; the mapping is conservative everywhere it
  /// can be.
  metered,

  /// No usable connection at all.
  none,
}

/// How this server's bytes would travel — F15's protection, or the lack of it.
///
/// The distinction exists because the playback socket is **not** F15's socket:
/// `filefin_api` pins the certificate on every request it makes, while libmpv
/// opens its own connection from native code and verifies nothing on it by
/// default. Measured both directions — `docs/field-notes.md`. D10 is what this
/// enum is consulted for.
enum PlaybackTransport {
  /// `http://` — nothing to verify. F1 already warns about this in words.
  plainHttp,

  /// `https://` with a certificate the OS trusts. libmpv is told
  /// `tls-verify=yes`, so its own connection is checked against the system
  /// roots even though the pin is not consulted.
  osTrustedTls,

  /// `https://` with a certificate only **we** trust, through F15's pin.
  ///
  /// This is the case libmpv cannot reproduce: it has no pin, and turning
  /// verification on would refuse the certificate the user deliberately
  /// accepted. See [RefuseReason.unverifiablePlaybackTls].
  pinnedTls,
}

/// Why playback was refused outright.
///
/// Every variant is constructible from [decide]'s own inputs, which is the test
/// for whether a reason belongs here. A `415 transcoding disabled` is only
/// knowable *after* a request, so it is not a branch of this function: the
/// variant is `filefin_api`'s (`TranscodingDisabled`, raised by
/// `requirePlayable`) and the wording is `apps/mobile`'s, because this package
/// draws nothing.
enum RefuseReason {
  /// [NetworkType.none] — there is nothing to stream over.
  offline,

  /// The connection is metered and the server's "wifi only" setting is on.
  wifiOnlyOnMetered,

  /// [PlaybackTransport.pinnedTls] without the per-server override.
  ///
  /// The default is to refuse, because the alternative is to hand the session
  /// cookie to a peer whose certificate nothing checked. The override exists
  /// because for a self-hosted server on a LAN that is often the *only* way to
  /// play anything, and it is the user's call to make — once, per server, with
  /// a banner that stays up for as long as it is in effect.
  unverifiablePlaybackTls,
}

/// The per-server playback settings [decide] consults.
///
/// [progressIntervalSecs] is not read by [decide] at all: it is the interval
/// `decideReport` measures against, and it lives here because the three are one
/// **sheet in the UI**. They are not one block on disk, and an earlier draft of
/// this sentence said they were (corrected at M4.R/P7): `wifiOnly` and
/// `allowUnverifiedPlayback` are fields on each `SavedServer`, while
/// `meteredWarnBytes` and `progressIntervalSecs` are the global `PlaybackPrefs`
/// block — which is exactly why the settings sheet reports the two halves
/// separately and `app.dart` writes them separately. Upstream's own player uses
/// **30 media seconds** (`web/src/views/library/Player.svelte`), which is the
/// default `PlaybackPrefs` writes.
@freezed
abstract class PlaybackSettings with _$PlaybackSettings {
  /// [wifiOnly] refuses metered playback outright; [meteredWarnBytes] is the
  /// size above which a metered attempt asks first; [progressIntervalSecs] is
  /// how far playback must move before a checkpoint is reported.
  const factory PlaybackSettings({
    required bool wifiOnly,
    required int meteredWarnBytes,
    required int progressIntervalSecs,
  }) = _PlaybackSettings;
}

/// What should happen when the user asks to play a file.
///
/// Sealed, so a caller's `switch` is exhaustive without a `default` arm nobody
/// can test.
sealed class PlaybackDecision {
  /// Allows the const subclasses below.
  const PlaybackDecision();
}

/// Playback that can start immediately.
///
/// This intermediate layer is deliberate: [ConfirmLargeOnMetered] has to carry
/// what happens *after* confirmation, and typing that as `PlayNow` rather than
/// `PlaybackDecision` keeps a caller's switch exhaustive without an assert that
/// no test can reach. There is no `Refuse` on the far side of a confirmation.
sealed class PlayNow extends PlaybackDecision {
  /// Allows the const subclasses below.
  const PlayNow();
}

/// Fetch `GET .../file/{n}` as raw bytes, with full seek.
final class PlayDirect extends PlayNow {
  /// The server will serve this file's own bytes.
  const PlayDirect();
}

/// Follow the `307` to the HLS playlist.
final class PlayHls extends PlayNow {
  /// The server will transcode this file to HLS.
  const PlayHls();
}

/// Metered connection, and the file is larger than the configured threshold.
///
/// [bytes] is the actual size, so the prompt can name it rather than saying
/// "this file is large".
final class ConfirmLargeOnMetered extends PlaybackDecision {
  /// Ask about [bytes], then do [proceed] if the user accepts.
  const ConfirmLargeOnMetered({required this.bytes, required this.proceed});

  /// The file's size in bytes, from `fileInfo.size`.
  final int bytes;

  /// What to do once the user accepts.
  final PlayNow proceed;
}

/// Playback will not start, for a reason knowable without asking the server.
final class Refuse extends PlaybackDecision {
  /// Refuse for [reason].
  const Refuse(this.reason);

  /// Why.
  final RefuseReason reason;
}

/// Decides whether — and how — to start playing [file] (SPEC.md §5.4, F13).
///
/// A **guard**, not a switch (D4): the server exposes no quality or bitrate
/// parameter, so the only thing this varies is whether playback starts at all.
/// The mode comes from [FileInfo.transcode], the server's own verdict.
/// [transport] and [allowUnverifiedPlayback] are D10, both required so a call
/// site cannot forget the question.
///
/// **Order matters, each step being a superset of the next:** offline, then an
/// unverifiable transport (it refuses at every size on every network), then
/// wifi-only, then size — which asks only *strictly above* the threshold.
PlaybackDecision decide(
  FileInfo file,
  NetworkType network,
  PlaybackSettings settings, {
  required PlaybackTransport transport,
  required bool allowUnverifiedPlayback,
}) {
  final mode = file.transcode ? const PlayHls() : const PlayDirect();

  if (network == NetworkType.none) {
    return const Refuse(RefuseReason.offline);
  }
  if (transport == PlaybackTransport.pinnedTls && !allowUnverifiedPlayback) {
    return const Refuse(RefuseReason.unverifiablePlaybackTls);
  }
  if (network == NetworkType.metered) {
    if (settings.wifiOnly) {
      return const Refuse(RefuseReason.wifiOnlyOnMetered);
    }
    if (file.size > settings.meteredWarnBytes) {
      return ConfirmLargeOnMetered(bytes: file.size, proceed: mode);
    }
  }
  return mode;
}
