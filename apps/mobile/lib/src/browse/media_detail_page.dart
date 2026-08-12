import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/detail_header.dart';
import 'package:filefin_mobile/src/browse/detail_sections.dart';
import 'package:filefin_mobile/src/browse/episode_list.dart';
import 'package:filefin_mobile/src/browse/file_list.dart' show fileLabel;
import 'package:filefin_mobile/src/browse/watch_actions.dart';
import 'package:filefin_mobile/src/browse/watch_state_controls.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:flutter/material.dart';

/// F4's third screen: everything the server says about one item, and where
/// playback starts (F8).
///
/// **The redesign's order is resume, then episodes, then everything else.** The
/// old screen led with a poster and eleven metadata blocks and put the episode
/// a person came for below all of them; the header is now 186 points of art
/// with the title on it, the action row sits directly under it, and the
/// description, cast, ratings and file paths are behind two disclosure rows.
class MediaDetailPage extends StatefulWidget {
  /// Shows [item]'s detail, fetched through [api].
  const MediaDetailPage({
    required this.api,
    required this.item,
    this.onPlay,
    this.onSignIn,
    super.key,
  });

  /// Where the detail and the poster come from.
  final LibraryApi api;

  /// The list entry that was tapped. Its title is what the header shows until
  /// the real one arrives, so the screen is never nameless.
  final MediaSummary item;

  /// Opens the player on one file of the item, at a start position.
  ///
  /// The route lives in `app.dart`; this screen decides only **which file and
  /// from where**, which is `startSecondsFor`'s answer rather than its own.
  ///
  /// **It answers with what playback left behind**, which is what F9's second
  /// clause needs a consumer for — see `_MediaDetailPageState._afterPlaying`.
  final Future<PlaybackOutcome?> Function(
    MediaDetail detail,
    FileIndex file,
    Duration startAt,
  )?
  onPlay;

  /// Where a `SessionExpired` sends the user.
  final VoidCallback? onSignIn;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  late final AsyncController<MediaDetail> _controller =
      AsyncController<MediaDetail>(
        (token) => widget.api.mediaDetail(widget.item.id, cancelToken: token),
      );

  late final WatchActions _watch = WatchActions(
    api: widget.api,
    publish: _controller.replace,
  );

  final _posterToken = CancelToken();

  /// Whether a playback session on this screen wrote progress to the server.
  ///
  /// Kept here rather than folded into [WatchActions] because it is not one of
  /// F10's writes: it is F9's, made by the player route this screen pushed. It
  /// has the same consequence — the server re-stamped `updated`, and `updated`
  /// orders all three home rows (M6.0/E-3) — so it has to reach the same pop.
  bool _playbackWrote = false;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _posterToken.cancel();
    _watch.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// F9's "reflect resulting watched/continue changes locally **without a full
  /// refetch**", applied to the screen the player was opened from.
  ///
  /// `applyProgress` is the server's own engine transcribed and validated
  /// against 601 captured vectors, so the state the player hands back IS what
  /// the server holds — for every input but one. That one is
  /// [PlaybackOutcome.needsDetailRefetch]: a crossing report on a single-file
  /// item, where the wire's `(0, 0)` cannot say whether the pointer is fresh or
  /// absent. There, and only there, this pays for a round trip.
  ///
  /// Until M4.R/P3 neither branch existed and the screen simply showed what it
  /// had loaded in `initState` — so after watching half a film the detail page
  /// behind still offered to resume from where the *previous* session stopped.
  Future<void> _afterPlaying(
    MediaDetail detail,
    FileIndex file,
    Duration startAt,
  ) async {
    final outcome = await widget.onPlay!(detail, file, startAt);
    if (outcome == null || !mounted) return;
    // Before the two returns below, because both are about THIS screen and the
    // home rows need reloading either way. Watching past 90% moves an item from
    // `continue` to `completed` on the server; without this Home kept showing
    // it under *Continue watching*, in its pre-playback position, for the rest
    // of the session (M6.R/P1.2).
    _playbackWrote = _playbackWrote || outcome.wrote;
    if (outcome.needsDetailRefetch) {
      await _controller.load();
      return;
    }
    final view = deriveView(outcome.state, fileCount: detail.files.length);
    _controller.replace(
      detail.copyWith(
        watched: view.watched,
        continueIndex: view.continueIndex.value,
        continueSeconds: view.continueSeconds,
      ),
    );
  }

  /// Pops with whether anything was written, so the home rows can be reloaded.
  ///
  /// **`canPop: false` and an explicit pop, because the ordinary back
  /// affordances carry no result.** The header's own back button and the system
  /// gesture both call `Navigator.maybePop(context)` with nothing, so a route
  /// pushed as `push<bool>` would receive null on every normal exit and the
  /// home rows would stay stale exactly when a write had happened.
  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      // `wroteOrWriting`, not `wrote`: this is read the instant the screen
      // closes, so a write still on the wire would otherwise pop `false` and
      // leave the rows stale for the rest of the session (M6.R/P1.3).
      //
      // `_playbackWrote` is the other half. F10's four writes are not the only
      // things that re-stamp `updated` — a progress report does too, and F9's
      // are the ones a user makes without touching a control.
      Navigator.of(context).pop(_watch.wroteOrWriting || _playbackWrote);
    },
    child: Scaffold(
      body: AsyncView<MediaDetail>(
        controller: _controller,
        onSignIn: widget.onSignIn,
        builder: (context, detail) => ListView(
          padding: EdgeInsets.zero,
          children: [
            DetailHeader(
              api: widget.api,
              detail: detail,
              actions: _watch,
              posterToken: _posterToken,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DetailActions(
                    detail: detail,
                    actions: _watch,
                    onPlay: widget.onPlay == null
                        ? null
                        : (file, startAt) =>
                              unawaited(_afterPlaying(detail, file, startAt)),
                  ),
                  WatchStateNotice(actions: _watch),
                ],
              ),
            ),
            EpisodeList(
              files: detail.files,
              onPlay: widget.onPlay == null
                  ? null
                  : (file) => unawaited(
                      _afterPlaying(
                        detail,
                        file,
                        Duration(seconds: startSecondsFor(detail, file)),
                      ),
                    ),
            ),
            DetailSections(detail: detail, actions: _watch),
          ],
        ),
      ),
    ),
  );
}

/// F8's action row: resume where the pointer is, start over, mark watched.
///
/// The resume label comes from `offerResume`, which is **upstream's own rule
/// observed rather than invented** — `!watched && (continueIndex > 0 ||
/// continueSeconds > 0)`. The ambiguous `(0, 0)` is never offered, so this
/// screen can never propose a resume position it made up.
class DetailActions extends StatelessWidget {
  /// Offers playback of [detail], and its watched state through [actions].
  const DetailActions({
    required this.detail,
    required this.actions,
    required this.onPlay,
    super.key,
  });

  /// The item.
  final MediaDetail detail;

  /// Where the watched control writes to.
  final WatchActions actions;

  /// Starts one file at a position, or null when this screen cannot play.
  final void Function(FileIndex file, Duration startAt)? onPlay;

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    final play = onPlay;
    final choice = detail.files.isEmpty || play == null
        ? null
        : offerResume(detail);
    return Row(
      children: [
        if (play != null && detail.files.isNotEmpty) ...[
          Expanded(
            child: _PrimaryButton(
              palette: palette,
              label: choice is ResumeAvailable
                  ? resumeLabel(detail, choice)
                  : 'Play',
              onPressed: () => switch (choice) {
                ResumeAvailable(:final file, :final seconds) => play(
                  file,
                  Duration(seconds: seconds),
                ),
                _ => play(const FileIndex(0), Duration.zero),
              },
            ),
          ),
          const SizedBox(width: 8),
          if (choice is ResumeAvailable)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Start over',
                child: OutlinedButton(
                  onPressed: () => play(const FileIndex(0), Duration.zero),
                  style: _squareStyle(palette),
                  child: const Icon(Icons.replay, size: 18),
                ),
              ),
            ),
        ],
        WatchedButton(detail: detail, actions: actions),
      ],
    );
  }

  static ButtonStyle _squareStyle(FileFinPalette palette) =>
      OutlinedButton.styleFrom(
        fixedSize: const Size.square(44),
        minimumSize: const Size.square(44),
        padding: EdgeInsets.zero,
        foregroundColor: palette.textMuted,
        side: BorderSide(color: palette.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
}

/// The words on the resume button.
///
/// The design writes it `Resume S2E2 · 1:46`. Naming the file is worth the
/// width only when the name **identifies** it, which is two conditions rather
/// than one:
///
/// - a single-file item has nothing to disambiguate, and `fileLabel` would
///   print the file's own name so the button would carry the title twice;
/// - a multi-file item whose files carry neither a season, an episode nor a
///   name falls back to `File 0`, which is `fileLabel`'s way of saying it does
///   not know — and putting that on the primary action tells the user nothing
///   while costing them the clock's legibility.
///
/// Public only so a test can reach it; nothing outside this library calls it
/// (§5, `public_member_no_consumer`).
@visibleForTesting
String resumeLabel(MediaDetail detail, ResumeAvailable choice) {
  final clock = _clock(choice.seconds);
  if (detail.files.length < 2) return 'Resume $clock';
  final file = detail.files.firstWhere(
    (f) => f.index == choice.file,
    orElse: () => detail.files.first,
  );
  final named = file.season > 0 || file.episode > 0 || file.name.isNotEmpty;
  return named ? 'Resume ${fileLabel(file)} · $clock' : 'Resume $clock';
}

String _clock(int seconds) {
  // One constant for both, and the reason is the mutation gate's rather than
  // style's: Dart defines `a % b` to land in `[0, b.abs())`, so `% 60` and
  // `% -60` are the same function and a bare literal produces a mutant no
  // assertion can kill. Shared with the `~/` below, the same mutation turns
  // `Resume 2:05` into `Resume -2:05`, which a test does object to.
  // `formatPosition` in `player_controls.dart` carries the same note; the two
  // are not merged because that would make `browse` depend on `playback`.
  const perMinute = 60;
  final s = (seconds % perMinute).toString().padLeft(2, '0');
  return '${seconds ~/ perMinute}:$s';
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.palette,
    required this.label,
    required this.onPressed,
  });

  final FileFinPalette palette;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.play_arrow, size: 16),
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(44),
      backgroundColor: palette.accentFill,
      foregroundColor: palette.accentSoft,
      side: BorderSide(color: palette.accentBright),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
