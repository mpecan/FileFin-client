import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/file_list.dart';
import 'package:filefin_mobile/src/browse/poster_image_provider.dart';
import 'package:filefin_mobile/src/browse/watch_actions.dart';
import 'package:filefin_mobile/src/browse/watch_state_controls.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart'
    show PlaybackOutcome;
import 'package:flutter/material.dart';

/// F4's third screen: everything the server says about one item, and where
/// playback starts (F8).
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

  /// The list entry that was tapped. Its title is the app-bar title until the
  /// real one arrives, so the screen is never nameless.
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
  /// affordances carry no result.** A `Scaffold`'s own back button and the
  /// system gesture both call `Navigator.maybePop(context)` with nothing, so a
  /// route pushed as `push<bool>` would receive null on every normal exit and
  /// the home rows would stay stale exactly when a write had happened.
  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      // `wroteOrWriting`, not `wrote`: this is read the instant the screen
      // closes, so a write still on the wire would otherwise pop `false` and
      // leave the rows stale for the rest of the session (M6.R/P1.3).
      Navigator.of(context).pop(_watch.wroteOrWriting);
    },
    child: _scaffold(context),
  );

  Widget _scaffold(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.item.title.isEmpty ? 'Untitled' : widget.item.title,
      ),
    ),
    body: AsyncView<MediaDetail>(
      controller: _controller,
      onSignIn: widget.onSignIn,
      builder: (context, detail) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (detail.hasPoster)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: Image(
                  image: PosterImageProvider(
                    api: widget.api,
                    media: detail.id,
                    size: PosterSize.detail,
                    cancelToken: _posterToken,
                  ),
                  errorBuilder: (context, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          _Heading(detail: detail),
          if (detail.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(detail.description),
          ],
          // Both, when both exist. `description` is the short line and `plot`
          // the long one (`media.go:56`), and they are genuinely different
          // fields rather than two names for one — showing only the first
          // would drop whichever the importer happened to fill.
          if (detail.plot.isNotEmpty && detail.plot != detail.description) ...[
            const SizedBox(height: 12),
            Text(detail.plot),
          ],
          _Chips(label: 'Genres', values: detail.genres),
          _Chips(label: 'Tags', values: detail.tags),
          _Chips(label: 'Cast', values: detail.actors),
          _Pairs(label: 'Details', pairs: detail.metadata),
          _Pairs(label: 'Ratings', pairs: detail.ratings),
          _Pairs(label: 'Technical', pairs: detail.technical),
          WatchStateControls(detail: detail, actions: _watch),
          if (widget.onPlay != null)
            PlayButtons(
              detail: detail,
              onPlay: (file, startAt) =>
                  unawaited(_afterPlaying(detail, file, startAt)),
            ),
          FileList(
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
        ],
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.detail});

  final MediaDetail detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detail.title.isEmpty ? 'Untitled' : detail.title,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        // A year of 0 is the model's default for a payload with no year, not a
        // film from the year zero.
        if (detail.year != 0)
          Text(
            '${detail.year}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
      ],
    ),
  );
}

/// A labelled row of chips, or nothing at all when the list is empty.
///
/// **An empty rich block is normal, not an error.** An un-enriched library has
/// no genres, no cast and no ratings, and a section header over nothing would
/// read as something missing rather than something absent.
class _Chips extends StatelessWidget {
  const _Chips({required this.label, required this.values});

  final String label;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [for (final value in values) Chip(label: Text(value))],
          ),
        ],
      ),
    );
  }
}

/// A labelled list of key/value rows, rendered **exactly as sent**.
///
/// `MetaPair.key` is a DISPLAY LABEL, not an identifier. The server renders
/// `metadata` and `ratings` through `metadataLabels`/`ratingLabels`
/// (`media.go:80,93`): a listed key gets a friendly label and everything else
/// falls through sorted under its raw name. The captured fixture carries
/// `customKey` precisely to keep that honest — a client that switched on the
/// key would silently drop every field the server's label table does not know.
class _Pairs extends StatelessWidget {
  const _Pairs({required this.label, required this.pairs});

  final String label;
  final List<MetaPair> pairs;

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final pair in pairs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 140, child: Text(pair.key)),
                  Expanded(child: Text(pair.value)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// F8's two buttons: *Continue* where the pointer is, or *Play* from the top.
///
/// The label comes from `offerResume`, which is **upstream's own rule observed
/// rather than invented** — `!watched && (continueIndex > 0 ||
/// continueSeconds > 0)`. The ambiguous `(0, 0)` is never offered, so this
/// screen can never propose a resume position it made up.
class PlayButtons extends StatelessWidget {
  /// Offers playback of [detail].
  const PlayButtons({required this.detail, required this.onPlay, super.key});

  /// The item.
  final MediaDetail detail;

  /// Starts one file at a position.
  final void Function(FileIndex file, Duration startAt) onPlay;

  @override
  Widget build(BuildContext context) {
    if (detail.files.isEmpty) return const SizedBox.shrink();
    final choice = offerResume(detail);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          if (choice case ResumeAvailable(:final file, :final seconds)) ...[
            FilledButton.icon(
              onPressed: () => onPlay(file, Duration(seconds: seconds)),
              icon: const Icon(Icons.play_arrow),
              label: Text('Continue ${_clock(seconds)}'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => onPlay(const FileIndex(0), Duration.zero),
              child: const Text('Start over'),
            ),
          ] else
            FilledButton.icon(
              onPressed: () => onPlay(const FileIndex(0), Duration.zero),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
        ],
      ),
    );
  }

  static String _clock(int seconds) {
    // One constant for both, and the reason is the mutation gate's rather than
    // style's: Dart defines `a % b` to land in `[0, b.abs())`, so `% 60` and
    // `% -60` are the same function and a bare literal produces a mutant no
    // assertion can kill. Shared with the `~/` below, the same mutation turns
    // `Continue 2:05` into `Continue -2:05`, which a test does object to.
    // `formatPosition` in `player_controls.dart` carries the same note; the two
    // are not merged because that would make `browse` depend on `playback`.
    const perMinute = 60;
    final s = (seconds % perMinute).toString().padLeft(2, '0');
    return '${seconds ~/ perMinute}:$s';
  }
}
