import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';

/// `mm:ss`, or `h:mm:ss` past an hour.
/// Public only so a test can reach it; nothing outside this library calls
/// it (§5, `public_member_no_consumer`).
@visibleForTesting
String formatPosition(Duration d) {
  // ONE named constant for both minute divisions rather than two literal 60s,
  // and it is the mutation gate that asks for it. Dart defines `a % b` to land
  // in `[0, b.abs())`, so `% 60` and `% -60` are the same function for every
  // input — two literals therefore produce two mutants that NO assertion can
  // kill, because no behaviour separates them. Routed through a constant, the
  // same mutation also rewrites the `~/` below, where the sign very much is
  // observable: `187 ~/ -60` is -3, and `3:07` becomes `57:07`. An equivalent
  // mutant turned into a killable one beats an exclusion (§3).
  const perMinute = 60;
  final seconds = d.inSeconds.clamp(0, 1 << 31);
  final s = (seconds % perMinute).toString().padLeft(2, '0');
  final m = (seconds ~/ perMinute) % perMinute;
  final h = seconds ~/ 3600;
  return h == 0 ? '$m:$s' : '$h:${m.toString().padLeft(2, '0')}:$s';
}

/// The two sizings the one overlay is drawn at.
///
/// A phone is held at arm's length and a television is watched from a sofa, so
/// the difference is not decoration: every number here is the design's, read
/// off the `player · landscape` frame and the `tv player · D-pad only` frame.
enum PlayerControlsMetrics {
  /// A phone in landscape.
  phone(
    margin: 22,
    barHeight: 64,
    iconSize: 22,
    titleSize: 15,
    factsSize: 11,
    playSize: 72,
    skipSize: 56,
    clockSize: 12,
    trackHeight: 4,
    showHints: false,
  ),

  /// A television, two metres away, driven by a D-pad.
  tv(
    margin: 56,
    barHeight: 76,
    iconSize: 26,
    titleSize: 26,
    factsSize: 15,
    playSize: 56,
    skipSize: 56,
    clockSize: 15,
    trackHeight: 6,
    showHints: true,
  );

  const PlayerControlsMetrics({
    required this.margin,
    required this.barHeight,
    required this.iconSize,
    required this.titleSize,
    required this.factsSize,
    required this.playSize,
    required this.skipSize,
    required this.clockSize,
    required this.trackHeight,
    required this.showHints,
  });

  /// The inset from the edge of the frame.
  final double margin;

  /// How tall the top bar is.
  final double barHeight;

  /// The size of a bare glyph on the top bar.
  final double iconSize;

  /// The item's name.
  final double titleSize;

  /// The mono line under it.
  final double factsSize;

  /// The play/pause target.
  final double playSize;

  /// The two seek targets beside it.
  final double skipSize;

  /// The position and duration readouts.
  final double clockSize;

  /// How thick the scrubber's track is.
  final double trackHeight;

  /// Whether to print what the remote's keys do.
  ///
  /// True on a television and false on a phone, and that asymmetry is the
  /// design's: a finger discovers a control by touching it, a D-pad cannot.
  final bool showHints;
}

/// Skip back, play or pause, skip forward.
///
/// Ten seconds each way, which is the interval the design's own hint strip
/// states — `◀▶ seek 10s`.
class PlayerTransport extends StatelessWidget {
  /// Drives [controller] at [metrics]' sizes.
  const PlayerTransport({
    required this.controller,
    required this.metrics,
    required this.onInteract,
    super.key,
  });

  /// The player being driven.
  final PlayerController controller;

  /// Phone or television sizing.
  final PlayerControlsMetrics metrics;

  /// Called whenever anything here is touched or focused.
  final VoidCallback onInteract;

  /// How far one press of a seek button moves.
  static const step = Duration(seconds: 10);

  /// Where a seek by [by] would land, never before the start.
  ///
  /// **Clamped at zero and nowhere else.** mpv reports a duration of zero for a
  /// stream it has not finished reading, so an upper clamp against
  /// `controller.duration` would refuse every forward seek in the first moments
  /// of an HLS playlist — which is exactly when a user skips a title sequence.
  /// Seeking past the end is the engine's to refuse.
  ///
  /// **`isNegative`, not `< Duration.zero`.** At exactly zero the two answers
  /// agree, so `<` rewritten to `<=` is a mutant nothing can kill; a predicate
  /// with no comparison operator in it has none to rewrite.
  ///
  /// Public only so a test can reach it; nothing outside this library calls it
  /// (§5, `public_member_no_consumer`). The annotation has to sit IMMEDIATELY
  /// above the declaration: `check_public_member_no_consumer` reads the one
  /// preceding line, so a doc comment slipped between the two turns the
  /// exemption off and the member is reported.
  @visibleForTesting
  static Duration seekTarget(Duration from, Duration by) {
    final target = from + by;
    return target.isNegative ? Duration.zero : target;
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      PlayerIconButton(
        icon: Icons.replay_10,
        tooltip: 'Back 10 seconds',
        size: metrics.skipSize * 0.46,
        onPressed: () =>
            controller.seekTo(seekTarget(controller.position, -step)),
        onInteract: onInteract,
      ),
      SizedBox(width: metrics.margin),
      _PlayButton(
        playing: controller.playing,
        size: metrics.playSize,
        onPressed: controller.togglePlay,
        onInteract: onInteract,
      ),
      SizedBox(width: metrics.margin),
      PlayerIconButton(
        icon: Icons.forward_10,
        tooltip: 'Forward 10 seconds',
        size: metrics.skipSize * 0.46,
        onPressed: () =>
            controller.seekTo(seekTarget(controller.position, step)),
        onInteract: onInteract,
      ),
    ],
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.size,
    required this.onPressed,
    required this.onInteract,
  });

  final bool playing;
  final double size;
  final VoidCallback onPressed;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    const palette = FileFinPalette.dark;
    return DpadFocusable(
      autofocus: true,
      onSelect: () {
        onPressed();
        onInteract();
      },
      onFocusChange: (focused) {
        if (focused) onInteract();
      },
      effects: const [DpadScaleEffect(scale: 1.1)],
      child: Tooltip(
        message: playing ? 'Pause' : 'Play',
        child: SizedBox.square(
          dimension: size,
          child: IconButton(
            onPressed: () {
              onPressed();
              onInteract();
            },
            style: IconButton.styleFrom(
              backgroundColor: palette.accentFill,
              foregroundColor: palette.text,
              side: BorderSide(color: palette.accent),
              shape: const CircleBorder(),
            ),
            iconSize: size * 0.39,
            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
          ),
        ),
      ),
    );
  }
}

/// The bottom half: the scrubber, its clocks, and what is next.
class PlayerScrubber extends StatelessWidget {
  /// Scrubs [controller] at [metrics]' sizes.
  const PlayerScrubber({
    required this.controller,
    required this.metrics,
    required this.onInteract,
    super.key,
  });

  /// The player being scrubbed.
  final PlayerController controller;

  /// Phone or television sizing.
  final PlayerControlsMetrics metrics;

  /// Called whenever anything here is touched or focused.
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    const palette = FileFinPalette.dark;
    final duration = controller.duration;
    // ONE guard, read twice, rather than `max <= 0` written out three times.
    // The three copies were not a style problem: `.clamp(0, max.toInt())` ran
    // BEFORE any of them, so a negative duration — which mpv can report for a
    // stream it has not finished reading — threw `ArgumentError: 0` out of
    // `build` and took the whole screen with it. Found by writing the
    // assertion the mutation gate asked for.
    final lengthMs = duration.inMilliseconds;
    final scrubbable = lengthMs > 0;
    final max = scrubbable ? lengthMs.toDouble() : 1.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              formatPosition(controller.position),
              style: mono(size: metrics.clockSize, color: palette.text),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: metrics.trackHeight,
                  inactiveTrackColor: palette.outlineStrong,
                ),
                child: DpadFocusable(
                  // A D-pad has no drag: left and right seek by ten seconds
                  // while the scrubber holds focus, which is what the design's
                  // `◀▶ seek 10s` hint promises.
                  onDirection: _nudge,
                  onFocusChange: (focused) {
                    if (focused) onInteract();
                  },
                  // Named, and INSIDE the focusable rather than around it: a
                  // focus ring on a bare bar says only "you are here" and not
                  // what pressing anything will do, and a name on an ancestor
                  // is not the focused node's name — so a screen reader, and
                  // the reachability walk, would both find it unlabelled.
                  child: Tooltip(
                    message: 'Seek',
                    child: Slider(
                      // A scrubber reporting on every frame of a drag would
                      // post a request per pixel. `onChangeEnd` fires once,
                      // when the finger lifts — which is when the seek is
                      // real.
                      value: controller.position.inMilliseconds
                          .clamp(0, max.toInt())
                          .toDouble(),
                      max: max,
                      onChanged: scrubbable ? (_) {} : null,
                      onChangeEnd: scrubbable
                          ? (v) => controller.seekTo(
                              Duration(milliseconds: v.round()),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              formatPosition(duration),
              style: mono(size: metrics.clockSize, color: palette.textMuted),
            ),
          ],
        ),
        Row(
          children: [
            if (controller.hasPrevious)
              PlayerPill(
                icon: Icons.skip_previous,
                label: 'Previous',
                metrics: metrics,
                onPressed: controller.previous,
                onInteract: onInteract,
              ),
            if (controller.hasNext)
              PlayerPill(
                icon: Icons.skip_next,
                label: 'Next',
                metrics: metrics,
                onPressed: controller.next,
                onInteract: onInteract,
              ),
            const Spacer(),
            if (metrics.showHints)
              Text(
                'OK pause   ◀▶ seek 10s   BACK exit',
                style: mono(size: 14, color: palette.textFaint),
              )
            else
              _Volume(controller: controller, onInteract: onInteract),
          ],
        ),
      ],
    );
  }

  bool _nudge(TraversalDirection direction) {
    final by = switch (direction) {
      TraversalDirection.left => -PlayerTransport.step,
      TraversalDirection.right => PlayerTransport.step,
      TraversalDirection.up || TraversalDirection.down => null,
    };
    if (by == null) return false;
    onInteract();
    unawaited(
      controller.seekTo(
        PlayerTransport.seekTarget(controller.position, by),
      ),
    );
    return true;
  }
}

/// The phone's volume slider.
///
/// Absent on the television, and that is the design's: a TV remote has its own
/// volume keys wired to the set's amplifier, and a second slider that moves
/// only mpv's gain is a control that appears not to work.
class _Volume extends StatelessWidget {
  const _Volume({required this.controller, required this.onInteract});

  final PlayerController controller;
  final VoidCallback onInteract;

  void _setVolume(double volume) {
    onInteract();
    unawaited(controller.setVolume(volume));
  }

  @override
  Widget build(BuildContext context) {
    const palette = FileFinPalette.dark;
    return SizedBox(
      width: 170,
      child: Row(
        children: [
          Icon(Icons.volume_up, size: 16, color: palette.textMuted),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: palette.textMuted,
                inactiveTrackColor: palette.outlineStrong,
              ),
              child: Slider(
                // The controller's value, never a literal: `value: 1` made the
                // thumb snap back to full on the next rebuild while mpv held
                // the dragged value, and mutating the literal to 0 left all
                // 149 playback tests green (M4.R/P6).
                value: controller.volume,
                onChanged: _setVolume,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A bare glyph on the overlay, focusable by a D-pad.
class PlayerIconButton extends StatelessWidget {
  /// Draws [icon] at [size]; a press calls [onPressed] and [onInteract].
  const PlayerIconButton({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onPressed,
    required this.onInteract,
    super.key,
  });

  /// The glyph.
  final IconData icon;

  /// What it is, for a screen reader and a long press.
  final String tooltip;

  /// How big the glyph is.
  final double size;

  /// What a press does.
  final VoidCallback onPressed;

  /// Called on a press and whenever this takes focus.
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) => DpadFocusable(
    onSelect: _press,
    onFocusChange: (focused) {
      if (focused) onInteract();
    },
    effects: const [DpadScaleEffect(scale: 1.2)],
    child: IconButton(
      onPressed: _press,
      tooltip: tooltip,
      iconSize: size,
      color: FileFinPalette.dark.text,
      icon: Icon(icon),
    ),
  );

  void _press() {
    onPressed();
    onInteract();
  }
}

/// A named, outlined pill — the design's replacement for an icon-only menu.
///
/// The whole point is the label: an icon-only audio button says a menu exists
/// and nothing about what is playing, which is what the design's `English` and
/// `Off` pills fix.
class PlayerPill extends StatelessWidget {
  /// Draws [icon] beside [label] at [metrics]' sizes.
  const PlayerPill({
    required this.icon,
    required this.label,
    required this.metrics,
    required this.onPressed,
    required this.onInteract,
    super.key,
  });

  /// The glyph on the left of the pill.
  final IconData icon;

  /// The word on it.
  final String label;

  /// Phone or television sizing.
  final PlayerControlsMetrics metrics;

  /// What a press does.
  final VoidCallback onPressed;

  /// Called on a press and whenever this takes focus.
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    const palette = FileFinPalette.dark;
    final tv = metrics == PlayerControlsMetrics.tv;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: DpadFocusable(
        onSelect: _press,
        onFocusChange: (focused) {
          if (focused) onInteract();
        },
        effects: const [DpadScaleEffect()],
        child: OutlinedButton.icon(
          onPressed: _press,
          icon: Icon(icon, size: tv ? 18 : 14),
          label: Text(label, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, tv ? 56 : 34),
            padding: EdgeInsets.symmetric(horizontal: tv ? 18 : 12),
            foregroundColor: palette.text,
            side: BorderSide(color: palette.outlineStrong),
            textStyle: TextStyle(fontSize: tv ? 15 : 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tv ? 8 : 17),
            ),
          ),
        ),
      ),
    );
  }

  void _press() {
    onPressed();
    onInteract();
  }
}
