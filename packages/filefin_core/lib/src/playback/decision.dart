import 'package:filefin_core/src/models/media_detail.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'decision.freezed.dart';

/// The connection a playback attempt would use.
enum NetworkType {
  /// Unmetered. Neither guard below applies.
  wifi,

  /// Metered — cellular, or a hotspot the OS reports as metered.
  metered,

  /// No usable connection at all.
  none,
}

/// Why playback was refused outright.
///
/// Both variants are constructible from [decide]'s own inputs, which is the
/// test for whether a reason belongs here. The `415 transcoding disabled`
/// message is only knowable *after* a request, so it is `filefin_api`'s to
/// report at M5, not a branch of this function.
enum RefuseReason {
  /// [NetworkType.none] — there is nothing to stream over.
  offline,

  /// The connection is metered and the server's "wifi only" setting is on.
  wifiOnlyOnMetered,
}

/// The per-server playback settings [decide] consults.
///
/// Two fields, because two levers exist. `progressIntervalSecs` arrives at M4
/// with the progress reporter that reads it; a settings field nobody reads is a
/// dead branch (§5).
@freezed
abstract class PlaybackSettings with _$PlaybackSettings {
  /// [wifiOnly] refuses metered playback outright; [meteredWarnBytes] is the
  /// size above which a metered attempt asks first.
  const factory PlaybackSettings({
    required bool wifiOnly,
    required int meteredWarnBytes,
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
/// The intent was to direct-play on wifi and transcode on cellular. The server
/// makes that impossible: `GET .../file/{n}` picks the mode from the probed
/// codecs alone, and there is no quality, bitrate or resolution parameter
/// anywhere. So this is a **guard**, not a switch. The only thing it can vary
/// is whether playback starts at all, using `fileInfo.size` — the only
/// bandwidth signal the API offers.
///
/// The mode comes from [FileInfo.transcode], **the server's own verdict**.
/// Reimplementing `transcode.DirectPlayable` here would be a second copy of a
/// decision the server has already made and told us, and it would drift.
///
/// Order matters, and each step is a superset of the next: offline refuses
/// before anything else is consulted; the wifi-only setting refuses before
/// the size is looked at; the size guard asks only **strictly above** the
/// threshold.
PlaybackDecision decide(
  FileInfo file,
  NetworkType network,
  PlaybackSettings settings,
) {
  final mode = file.transcode ? const PlayHls() : const PlayDirect();

  if (network == NetworkType.none) {
    return const Refuse(RefuseReason.offline);
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
