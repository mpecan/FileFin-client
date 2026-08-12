import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// libmpv, as narrowly as this app uses it.
///
/// **One of exactly two files allowed to import `package:media_kit`**
/// (`app_no_raw_http`, `tool/check-constitution.sh`). It is pure delegation:
/// every decision — what to open, where to start, which track, when to report —
/// lives in `MediaKitPlaybackHost` and `PlayerController` over this interface,
/// so all of it is tested against `FakeMpvPlayer` with no libmpv at all.
abstract base class MpvPlayer {
  /// Allows implementations to be `const`.
  const MpvPlayer();

  /// Where playback is now.
  Stream<Duration> get position;

  /// How long the current file is.
  Stream<Duration> get duration;

  /// Whether playback is running.
  Stream<bool> get playing;

  /// Fires at the end of the file.
  Stream<bool> get completed;

  /// The tracks libmpv found, in libmpv's own shape.
  Stream<Tracks> get tracks;

  /// Whatever libmpv failed at, in its own words.
  Stream<String> get errors;

  /// Loads [media].
  Future<void> open(Media media);

  /// Resumes.
  Future<void> play();

  /// Pauses.
  Future<void> pause();

  /// Seeks.
  Future<void> seek(Duration position);

  /// Sets the volume on libmpv's own **0..100** scale.
  Future<void> setVolume(double percent);

  /// Switches audio track.
  Future<void> setAudioTrack(AudioTrack track);

  /// Switches subtitle track, [SubtitleTrack.no] for off.
  Future<void> setSubtitleTrack(SubtitleTrack track);

  /// Sets one mpv property — `tls-verify`, and nothing else today.
  Future<void> setProperty(String name, String value);

  /// The video surface. Not reachable under `flutter test`.
  Widget buildSurface({
    VoidCallback? onBack,
    VoidCallback? onShowSubtitles,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
    String? title,
  });

  /// Releases the mpv context.
  Future<void> dispose();
}

/// The real thing: one [Player], and nothing else.
final class RealMpvPlayer extends MpvPlayer {
  /// Builds a player, initialising libmpv **before** constructing it.
  factory RealMpvPlayer({String? libmpv}) {
    MediaKit.ensureInitialized(libmpv: libmpv);
    return RealMpvPlayer.over(Player());
  }

  /// Wraps an already-built [Player] — the headless suite's way in.
  RealMpvPlayer.over(this._player);

  final Player _player;
  VideoController? _controller;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Stream<Tracks> get tracks => _player.stream.tracks;

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Future<void> open(Media media) => _player.open(media);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double percent) => _player.setVolume(percent);

  @override
  Future<void> setAudioTrack(AudioTrack track) => _player.setAudioTrack(track);

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) =>
      _player.setSubtitleTrack(track);

  @override
  Future<void> setProperty(String name, String value) =>
      (_player.platform! as NativePlayer).setProperty(name, value);

  @override
  Widget buildSurface({
    VoidCallback? onBack,
    VoidCallback? onShowSubtitles,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
    String? title,
  }) {
    final video = Video(
      controller: _controller ??= VideoController(_player),
      pauseUponEnteringBackgroundMode: false,
    );
    return _VideoControls(
      player: _player,
      video: video,
      onBack: onBack,
      onShowSubtitles: onShowSubtitles,
      onNext: onNext,
      onPrevious: onPrevious,
      title: title,
    );
  }

  @override
  Future<void> dispose() => _player.dispose();
}

/// Full-screen video with auto-fading, D-pad-navigable controls.
///
/// A tap anywhere or a D-pad select/up/down shows the controls, which fade
/// out after 8 seconds. Every button is wrapped in [DpadFocusable] so the
/// D-pad can move between them once visible.
class _VideoControls extends StatefulWidget {
  const _VideoControls({
    required this.player,
    required this.video,
    this.onBack,
    this.onShowSubtitles,
    this.onNext,
    this.onPrevious,
    this.title,
  });

  final Player player;
  final Widget video;
  final VoidCallback? onBack;
  final VoidCallback? onShowSubtitles;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final String? title;

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  var _playing = false;
  var _visible = true;
  Timer? _fadeTimer;

  @override
  void initState() {
    super.initState();
    widget.player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    });
    _resetFade();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  void _show() {
    _fadeTimer?.cancel();
    if (!_visible) setState(() => _visible = true);
    _resetFade();
  }

  void _resetFade() {
    _fadeTimer?.cancel();
    _fadeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _show,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(child: widget.video),
          AnimatedOpacity(
            opacity: _visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: SafeArea(
              child: Column(
                children: [
                  _topBar(),
                  const Spacer(),
                  _centerButtons(),
                  const Spacer(),
                  _bottomProgress(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (widget.onBack != null)
            _Btn(
              icon: Icons.arrow_back,
              onPressed: widget.onBack!,
              onInteract: _show,
            ),
          if (widget.title != null && widget.title!.isNotEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.title!,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          if (widget.onShowSubtitles != null)
            _Btn(
              icon: Icons.subtitles,
              onPressed: widget.onShowSubtitles!,
              onInteract: _show,
            ),
        ],
      ),
    );
  }

  Widget _centerButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.onPrevious != null)
            _Btn(
              icon: Icons.skip_previous,
              onPressed: widget.onPrevious!,
              onInteract: _show,
            ),
          const SizedBox(width: 24),
          _PlayBtn(
            playing: _playing,
            player: widget.player,
            onInteract: _show,
          ),
          const SizedBox(width: 24),
          if (widget.onNext != null)
            _Btn(
              icon: Icons.skip_next,
              onPressed: widget.onNext!,
              onInteract: _show,
            ),
        ],
      ),
    );
  }

  Widget _bottomProgress() {
    return StreamBuilder<Duration>(
      stream: widget.player.stream.position,
      initialData: Duration.zero,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: widget.player.stream.duration,
          initialData: Duration.zero,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final dur = durSnap.data ?? Duration.zero;
            final max = dur.inMilliseconds.toDouble();
            final value = pos.inMilliseconds.clamp(0, max.toInt()).toDouble();
            return DpadFocusable(
              onDirection: (dir) {
                if (dir == TraversalDirection.left ||
                    dir == TraversalDirection.right) {
                  final offset = dir == TraversalDirection.right
                      ? const Duration(seconds: 10)
                      : const Duration(seconds: -10);
                  final target = pos + offset;
                  widget.player.seek(
                    target < Duration.zero ? Duration.zero : target,
                  );
                  return true;
                }
                return false;
              },
              effects: const [
                DpadBorderEffect(color: Colors.white70, width: 2),
              ],
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Text(
                      _fmt(pos),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: const SliderThemeData(
                          trackHeight: 2,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          value: value,
                          max: max > 0 ? max : 1.0,
                          onChanged: max > 0
                              ? (v) => widget.player.seek(
                                  Duration(milliseconds: v.round()),
                                )
                              : null,
                        ),
                      ),
                    ),
                    Text(
                      _fmt(dur),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _fmt(Duration d) {
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    final m = (d.inSeconds ~/ 60) % 60;
    final h = d.inHours;
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }
}

/// A D-pad-navigable icon button with a bright focus ring.
class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.onPressed,
    this.onInteract,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final VoidCallback? onInteract;

  @override
  Widget build(BuildContext context) => DpadFocusable(
    onSelect: () {
      onPressed();
      onInteract?.call();
    },
    onFocusChange: (focused) {
      if (focused) onInteract?.call();
    },
    effects: const [
      DpadScaleEffect(scale: 1.2),
      DpadBorderEffect(color: Colors.white, width: 3),
    ],
    child: IconButton(
      onPressed: () {
        onPressed();
        onInteract?.call();
      },
      icon: Icon(icon, color: Colors.white, size: 28),
    ),
  );
}

/// Circular play/pause button with a semi-transparent black background.
class _PlayBtn extends StatelessWidget {
  const _PlayBtn({
    required this.playing,
    required this.player,
    this.onInteract,
  });

  final bool playing;
  final Player player;
  final VoidCallback? onInteract;

  @override
  Widget build(BuildContext context) => DpadFocusable(
    onSelect: () {
      (playing ? player.pause : player.play)();
      onInteract?.call();
    },
    onFocusChange: (focused) {
      if (focused) onInteract?.call();
    },
    autofocus: true,
    effects: const [
      DpadScaleEffect(scale: 1.15),
      DpadBorderEffect(color: Colors.white, width: 3),
    ],
    child: Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.black87,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: playing ? player.pause : player.play,
        icon: Icon(
          playing ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
          size: 36,
        ),
      ),
    ),
  );
}
