import 'dart:async';

import 'package:filefin_mobile/src/browse/file_list.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:flutter/widgets.dart';

/// What the lock screen shows while an item plays (F14).
///
/// Deliberately three fields and no artwork. The poster is behind
/// `s.auth` and every media-session artwork API takes a **URI the OS
/// fetches for itself**, unauthenticated — so publishing one would either show
/// nothing or leak the session cookie into a request we do not control.
/// `browse/poster_image_provider.dart` carries the same reasoning for the
/// poster cache. It said `docs/architecture.md` until M7.R, and M7.9 had
/// deleted that paragraph in the same audit that corrected the diagram.
@immutable
class NowPlayingItem {
  /// The item's [title], the file's [subtitle], and how long the file is.
  const NowPlayingItem({
    required this.title,
    required this.subtitle,
    required this.duration,
  });

  /// The item — a film's name, a show's name.
  final String title;

  /// Which file of it, from [fileLabel]. Empty for a single-file item.
  final String subtitle;

  /// How long the file is, or zero before the engine knows.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is NowPlayingItem &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(title, subtitle, duration);

  @override
  String toString() => 'NowPlayingItem($title, $subtitle, $duration)';
}

/// Where the transport is, for the lock screen's scrubber and button (F14).
@immutable
class NowPlayingTransport {
  /// Playing or not, at [position], of [duration].
  const NowPlayingTransport({
    required this.playing,
    required this.position,
    required this.duration,
  });

  /// Whether the engine is playing.
  final bool playing;

  /// Where playback is.
  final Duration position;

  /// How long the file is.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is NowPlayingTransport &&
      other.playing == playing &&
      other.position == position &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(playing, position, duration);

  @override
  String toString() => 'NowPlayingTransport($playing, $position, $duration)';
}

/// A transport button the OS pressed, in **our** vocabulary.
///
/// Three, because three is what [NowPlayingBinder] can honour: the platform
/// vocabulary is far wider (skip, rate, queue) and a command with no consumer
/// is a dead branch (§1, §5).
sealed class TransportCommand {
  const TransportCommand();
}

/// Play, from the lock screen or a headset button.
final class ResumeCommand extends TransportCommand {
  /// The only instance there needs to be.
  const ResumeCommand();

  @override
  String toString() => 'ResumeCommand()';
}

/// Pause, from the lock screen or a headset button.
final class PauseCommand extends TransportCommand {
  /// The only instance there needs to be.
  const PauseCommand();

  @override
  String toString() => 'PauseCommand()';
}

/// Scrub, from the lock screen's own slider.
final class SeekCommand extends TransportCommand {
  /// Go to [to].
  const SeekCommand(this.to);

  /// Where the user dragged to.
  final Duration to;

  @override
  String toString() => 'SeekCommand($to)';
}

/// The OS's media session, as a port (F14).
///
/// The same shape as `PlaybackHost` and for the same reason: Android's
/// `MediaSession` plus a foreground service and iOS's `MPNowPlayingInfoCenter`
/// plus `MPRemoteCommandCenter` are platform surfaces with no headless
/// representation at all, so everything up to this boundary is testable and
/// only the boundary is not. No package type crosses it.
abstract class NowPlayingHost {
  /// Every transport button the OS pressed, in order.
  Stream<TransportCommand> get commands;

  /// Names what is playing. Called on open and on every file advance.
  Future<void> publish(NowPlayingItem metadata);

  /// Moves the transport. Called whenever the player's state changes.
  Future<void> update(NowPlayingTransport playback);

  /// Tears the session down, so the notification and the lock-screen control
  /// go away with the player screen.
  Future<void> clear();
}

/// Keeps a [NowPlayingHost] in step with one [PlayerController] (F14).
///
/// **Why the controller does not do this itself.** A media session is a second
/// consumer of the same state the screen draws, and `PlayerController` is
/// already the file-size gate's largest warning. More importantly it would put
/// a platform concern inside the state machine that F9's progress reports are
/// keyed on — and every one of M4.R's data-corruption defects lived in exactly
/// that sequencing. This observes and publishes; it decides nothing.
class NowPlayingBinder {
  /// Binds [session] to [controller] and publishes the first metadata at once.
  NowPlayingBinder({required this.session, required this.controller}) {
    _publish();
    controller.addListener(_onChange);
    _commands = session.commands.listen(_onCommand);
  }

  /// The OS session being driven.
  final NowPlayingHost session;

  /// The player it follows.
  final PlayerController controller;

  late final StreamSubscription<TransportCommand> _commands;
  NowPlayingItem? _publishedItem;
  NowPlayingTransport? _publishedTransport;

  NowPlayingItem _metadata() => NowPlayingItem(
    title: controller.detail.title,
    // Empty rather than a bare filename for a single-file item, because
    // `fileLabel` already answers "S1E2" or the extension and a lock screen
    // showing `movie.mkv` under the film's own title says nothing.
    subtitle: controller.detail.files.length == 1
        ? ''
        : fileLabel(controller.file),
    duration: controller.duration,
  );

  /// Publishes the metadata when — and only when — it has changed.
  ///
  /// **Keyed on the whole value rather than on the file index, and that is a
  /// defect found in review rather than a generalisation.** Keyed on the index
  /// alone, the item published at bind time carried `Duration.zero`, the
  /// adapter turned that into the platform's `null`, and nothing ever
  /// published it again for the file that was already playing — so the
  /// lock screen's scrubber had no length for the whole of the first file.
  /// mpv reports a duration a beat after the open, which is a change in the
  /// value and not in the index.
  void _publish() {
    final item = _metadata();
    if (item == _publishedItem) return;
    _publishedItem = item;
    unawaited(session.publish(item));
  }

  void _onChange() {
    // Covers F7's Next — a lock screen naming the wrong episode is backlog
    // row N's device check — and the duration arriving after the open.
    _publish();
    final now = NowPlayingTransport(
      playing: controller.playing,
      position: controller.position,
      duration: controller.duration,
    );
    // Position ticks arrive several times a second and every one of them is a
    // notify. Publishing an unchanged state across a platform channel that
    // often is the difference between a media session and a wakelock.
    if (now == _publishedTransport) return;
    _publishedTransport = now;
    unawaited(session.update(now));
  }

  Future<void> _onCommand(TransportCommand command) async {
    switch (command) {
      // Guarded rather than routed straight to `togglePlay`, because the OS
      // sends what its own button says and not what the engine is doing: a
      // headset `play` on an already-playing item would otherwise PAUSE it.
      case ResumeCommand():
        if (!controller.playing) await controller.togglePlay();
      case PauseCommand():
        if (controller.playing) await controller.togglePlay();
      case SeekCommand(:final to):
        await controller.seekTo(to);
    }
  }

  /// Stops following the player and takes the session down.
  ///
  /// The teardown is ordered, and the order is not cosmetic. `clear()` is
  /// awaited FIRST because it is the half a user can see — the notification
  /// and the lock-screen control going away with the screen — and it is fired
  /// unawaited from `PlayerPage.dispose`, where a frame is being built. The
  /// subscription is cancelled without awaiting for the same reason: nothing
  /// downstream depends on when it completes, and an extra suspension between
  /// the two is one more thing that has to be pumped before the visible half
  /// happens.
  Future<void> dispose() async {
    controller.removeListener(_onChange);
    unawaited(_commands.cancel());
    await session.clear();
  }
}
