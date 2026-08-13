import 'dart:async';

import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_top_bar.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Everything a person can do to playback (F7), drawn over the video.
///
/// **One overlay for the phone and the television**, differing only in the
/// sizes [PlayerControlsMetrics] carries. The alternative — a `TvPlayerPage`
/// beside `PlayerPage` — would have duplicated the auto-hide timer, the
/// scrubber's clamp and the track pickers, which is exactly the pair of
/// diverging control implementations this file was written to end.
///
/// **It fades, and a D-pad brings it back.** A remote has no pointer to move,
/// so any key press is what counts as interaction: every focusable child says
/// so when it takes focus, which is what makes the overlay reappear before the
/// button the user was aiming at is pressed.
class PlayerControls extends StatefulWidget {
  /// Draws the controls for [controller], titled [title] over [facts].
  const PlayerControls({
    required this.controller,
    required this.title,
    required this.facts,
    required this.metrics,
    this.onBack,
    this.onShowSubtitles,
    this.onShowAudio,
    super.key,
  });

  /// The player these controls drive.
  final PlayerController controller;

  /// The item's name, on the top bar.
  final String title;

  /// The mono line under it — which file, and how it is being served.
  final String facts;

  /// Phone or television sizing.
  final PlayerControlsMetrics metrics;

  /// Leaves the player. Null in a test that is not about leaving.
  final VoidCallback? onBack;

  /// Opens the subtitle picker.
  final VoidCallback? onShowSubtitles;

  /// Opens the audio-track picker.
  final VoidCallback? onShowAudio;

  /// How long the controls stay up after the last interaction.
  static const fadeAfter = Duration(seconds: 5);

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  var _visible = true;
  var _locked = false;
  Timer? _fade;

  /// Holds focus while the controls are hidden, so a remote has something to
  /// press keys at.
  ///
  /// **A television has nothing to tap.** A phone wakes the overlay by
  /// touching the glass; a TV has only the D-pad, and the faded overlay puts
  /// every control behind `ExcludeFocus` — so without this the film plays on
  /// with no way to pause it. `skipTraversal` keeps the node out of the arrow
  /// order once the controls are up, so it is never a stop on the way between
  /// two real buttons.
  //
  // No `debugLabel`: nothing reads it, and `just mutants` rewrites the string
  // to `player+wake` — a mutant no assertion can ever kill, because no
  // behaviour separates the two. A line that cannot be tested is a line §1
  // asks not to be written.
  final _wake = FocusNode();

  @override
  void initState() {
    super.initState();
    _restartFade();
  }

  @override
  void dispose() {
    _fade?.cancel();
    _wake.dispose();
    super.dispose();
  }

  /// Brings the controls back and restarts the countdown.
  ///
  /// Called by every child that takes focus, which is what makes a D-pad press
  /// wake the overlay, and by a tap on the picture that found them hidden.
  void _show() {
    if (!_visible) setState(() => _visible = true);
    _restartFade();
  }

  /// Takes the controls away, from the countdown or from a tap.
  ///
  /// The timer is cancelled rather than left to fire against an overlay that
  /// has already gone: a pending countdown outlives the tap that hid the
  /// controls and would then expire part-way through the next showing, which
  /// is a five-second promise kept for one.
  void _hide() {
    _fade?.cancel();
    setState(() => _visible = false);
    // Requested as the controls go, not before: until they do, focus belongs
    // to whichever button the user was on. A television that has been touched
    // once still has only the D-pad, so this is what it wakes them with.
    _wake.requestFocus();
  }

  /// What a tap on the picture does.
  ///
  /// **A toggle, not a show.** The scrim and the transport cover the frame,
  /// and while showing was the only thing a tap could do the sole way back to
  /// a clean picture was to touch nothing for five seconds — which every
  /// subsequent stray touch restarted. A tap on a *control* does not come
  /// here: the button's own recognizer is deeper in the hit-test order and
  /// takes the gesture arena, which is what leaves the transport up while it
  /// is being used.
  void _toggle() {
    if (_visible) {
      _hide();
    } else {
      _show();
    }
  }

  void _restartFade() {
    _fade?.cancel();
    _fade = Timer(PlayerControls.fadeAfter, () {
      if (mounted) _hide();
    });
  }

  /// Wakes the overlay on any key, and lets that key do nothing else.
  ///
  /// A user pressing down to see the controls has not asked to seek, and a
  /// press that both woke the overlay and acted would move the film before
  /// they could see where they were. Once visible this returns `ignored` and
  /// every key goes where it always did.
  KeyEventResult _wakeOnKey(FocusNode node, KeyEvent event) {
    if (_visible) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _show();
      // After the frame, because the controls are behind `ExcludeFocus` until
      // this rebuild lands and `nextFocus` would find nothing to move to. It
      // is what leaves focus on a real button rather than on this node, so the
      // next press acts instead of waking again.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _wake.nextFocus();
      });
    }
    return KeyEventResult.handled;
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    _restartFade();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = widget.metrics;
    return Focus(
      focusNode: _wake,
      skipTraversal: true,
      onKeyEvent: _wakeOnKey,
      child: GestureDetector(
        onTap: _toggle,
        behavior: HitTestBehavior.translucent,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          // Hidden controls must not be tappable: a tap on an invisible pause
          // button is a tap the user did not know they were making.
          child: IgnorePointer(
            ignoring: !_visible,
            child: ExcludeFocus(
              excluding: !_visible,
              child: DecoratedBox(
                decoration: const BoxDecoration(gradient: _scrim),
                child: SafeArea(
                  child: _locked
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: EdgeInsets.all(metrics.margin),
                            child: PlayerLockButton(
                              locked: true,
                              onPressed: _toggleLock,
                              onFocused: _show,
                            ),
                          ),
                        )
                      : _unlocked(metrics),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _unlocked(PlayerControlsMetrics metrics) => Padding(
    padding: EdgeInsets.symmetric(horizontal: metrics.margin),
    child: Column(
      children: [
        PlayerTopBar(
          controller: widget.controller,
          title: widget.title,
          facts: widget.facts,
          metrics: metrics,
          onBack: widget.onBack,
          onShowAudio: widget.onShowAudio,
          onShowSubtitles: widget.onShowSubtitles,
          onLock: _toggleLock,
          onInteract: _show,
        ),
        Expanded(
          child: Center(
            child: PlayerTransport(
              controller: widget.controller,
              metrics: metrics,
              onInteract: _show,
            ),
          ),
        ),
        PlayerScrubber(
          controller: widget.controller,
          metrics: metrics,
          onInteract: _show,
        ),
        SizedBox(height: metrics.margin),
      ],
    ),
  );
}

/// The wash that keeps white text legible over an arbitrary frame.
const _scrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: [0, 0.14, 0.38, 0.62, 1],
  colors: [
    Color(0xB80B0C14),
    Color(0x7A0B0C14),
    Color(0x000B0C14),
    Color(0x000B0C14),
    Color(0xDB0B0C14),
  ],
);
