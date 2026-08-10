import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
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

/// Everything a person can do to playback (F7).
class PlayerControls extends StatelessWidget {
  /// Draws the controls for [controller].
  const PlayerControls({required this.controller, super.key});

  /// The player these controls drive.
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
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
            Text(formatPosition(controller.position)),
            Expanded(
              child: Slider(
                // A scrubber that reported on every frame of a drag would post
                // a request per pixel. `onChangeEnd` fires once, when the
                // finger lifts, which is also when the seek is real.
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
            Text(formatPosition(duration)),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: controller.togglePlay,
              tooltip: controller.playing ? 'Pause' : 'Play',
              icon: Icon(
                controller.playing ? Icons.pause : Icons.play_arrow,
              ),
            ),
            _AudioMenu(controller: controller),
            _SubtitleMenu(controller: controller),
            IconButton(
              onPressed: controller.hasNext ? controller.next : null,
              tooltip: 'Next file',
              icon: const Icon(Icons.skip_next),
            ),
          ],
        ),
        Row(
          children: [
            const Icon(Icons.volume_up, size: 20),
            Expanded(
              child: Slider(
                // The controller's value, never a literal: `value: 1` made
                // the thumb snap back to full on the next rebuild while mpv
                // held the dragged value, and mutating the literal to 0 left
                // all 149 playback tests green (M4.R/P6).
                value: controller.volume,
                onChanged: controller.setVolume,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The audio tracks libmpv found.
///
/// **From the engine, not the API**, and that is C2 resolved rather than
/// ignored: `fileInfo` lists sidecar subtitles and no audio at all, so this is
/// the only place F7's audio selection can come from.
class _AudioMenu extends StatelessWidget {
  const _AudioMenu({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final tracks = controller.tracks.audio;
    return PopupMenuButton<PlaybackTrackRef>(
      tooltip: 'Audio track',
      enabled: tracks.isNotEmpty,
      onSelected: controller.selectAudio,
      itemBuilder: (_) => [
        for (final track in tracks)
          PopupMenuItem(value: track, child: Text(track.label)),
      ],
      // `icon:`, not `child:`. A bare `Icon` child is laid out at its own 24dp
      // and fails `androidTapTargetGuideline`; the icon form wraps it in the
      // 48dp target the guideline asks for.
      icon: const Icon(Icons.audiotrack),
    );
  }
}

/// The sidecar subtitles, plus Off.
///
/// **`onSelected` re-reads `controller.subtitles`, so it can be a different
/// list from the one `itemBuilder` numbered**, and the guard below is what
/// makes that survivable. `PlayerController._open()` replaces the list
/// wholesale and `_recover()` calls `_open()` asynchronously on any mpv error,
/// so an error while the menu is open followed by a tap on the last row
/// indexed past the end and threw a `RangeError` out of a callback. Third
/// instance of the same shape as the clamp-before-guard bug: a value computed
/// against one state, applied to another (M4.R/T9).
class _SubtitleMenu extends StatelessWidget {
  const _SubtitleMenu({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: 'Subtitles',
    onSelected: (index) => controller.selectSubtitle(
      index < 0 || index >= controller.subtitles.length
          ? null
          : controller.subtitles[index],
    ),
    itemBuilder: (_) => [
      const PopupMenuItem(value: -1, child: Text('Off')),
      for (var i = 0; i < controller.subtitles.length; i++)
        PopupMenuItem(value: i, child: Text(controller.subtitles[i].label)),
    ],
    icon: const Icon(Icons.subtitles),
  );
}
