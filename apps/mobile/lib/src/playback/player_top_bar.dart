import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';

/// The lock, which is the one control that survives locking.
///
/// Drawn twice: on the top bar beside the track pills, and on its own in the
/// margin once [locked] — which is what gives a locked overlay a way back.
class PlayerLockButton extends StatelessWidget {
  /// Draws the padlock in its [locked] state.
  const PlayerLockButton({
    required this.locked,
    required this.onPressed,
    required this.onFocused,
    super.key,
  });

  /// Whether the controls are currently locked.
  final bool locked;

  /// Flips the lock.
  final VoidCallback onPressed;

  /// Called whenever this takes focus.
  final VoidCallback onFocused;

  @override
  Widget build(BuildContext context) => PlayerIconButton(
    icon: locked ? Icons.lock : Icons.lock_open,
    tooltip: locked ? 'Unlock controls' : 'Lock controls',
    size: 20,
    onPressed: onPressed,
    onInteract: onFocused,
  );
}

/// The top bar: where you are, what is playing it, and the two track pills.
class PlayerTopBar extends StatelessWidget {
  /// Draws [title] over [facts], with [controller]'s current track labels.
  const PlayerTopBar({
    required this.controller,
    required this.title,
    required this.facts,
    required this.metrics,
    required this.onInteract,
    required this.onLock,
    this.onBack,
    this.onShowAudio,
    this.onShowSubtitles,
    super.key,
  });

  /// The player whose track labels are shown.
  final PlayerController controller;

  /// The item's name.
  final String title;

  /// The mono line under it.
  final String facts;

  /// Phone or television sizing.
  final PlayerControlsMetrics metrics;

  /// Called whenever anything here is touched or focused.
  final VoidCallback onInteract;

  /// Hides every control but the padlock.
  final VoidCallback onLock;

  /// Leaves the player.
  final VoidCallback? onBack;

  /// Opens the audio-track picker.
  final VoidCallback? onShowAudio;

  /// Opens the subtitle picker.
  final VoidCallback? onShowSubtitles;

  @override
  Widget build(BuildContext context) {
    const palette = FileFinPalette.dark;
    return SizedBox(
      height: metrics.barHeight,
      child: Row(
        children: [
          if (onBack != null)
            PlayerIconButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              size: metrics.iconSize,
              onPressed: onBack!,
              onInteract: onInteract,
            ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: metrics.titleSize,
                    fontWeight: FontWeight.w500,
                    color: palette.text,
                  ),
                ),
                Text(
                  facts,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(
                    size: metrics.factsSize,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onShowAudio != null)
            PlayerPill(
              icon: Icons.volume_up,
              label: audioLabel(controller),
              metrics: metrics,
              onPressed: onShowAudio!,
              onInteract: onInteract,
            ),
          if (onShowSubtitles != null)
            PlayerPill(
              icon: Icons.subtitles,
              label: controller.subtitle?.label ?? 'Off',
              metrics: metrics,
              onPressed: onShowSubtitles!,
              onInteract: onInteract,
            ),
          PlayerLockButton(
            locked: false,
            onPressed: onLock,
            onFocused: onInteract,
          ),
        ],
      ),
    );
  }
}

/// What the audio pill says.
///
/// **The label is the track the USER last chose, and says "Audio" before they
/// have.** libmpv's selected track is not on this app's engine port — `tracks`
/// reports what the file contains and nothing about which of them is playing —
/// so naming a track before a selection would be a guess. The design's
/// "English" is what the pill reads once one has been made.
///
@visibleForTesting
String audioLabel(PlayerController controller) =>
    controller.audio?.label ?? 'Audio';
