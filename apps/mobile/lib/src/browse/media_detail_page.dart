import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/async/async_controller.dart';
import 'package:filefin_mobile/src/async/async_view.dart';
import 'package:filefin_mobile/src/browse/poster_image_provider.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:flutter/material.dart';

/// F4's third screen: everything the server says about one item.
///
/// **No playback affordance.** M4 owns playback (SPEC.md §10), and a button
/// that did nothing would be a promise this milestone cannot keep.
class MediaDetailPage extends StatefulWidget {
  /// Shows [item]'s detail, fetched through [api].
  const MediaDetailPage({
    required this.api,
    required this.item,
    this.onSignIn,
    super.key,
  });

  /// Where the detail and the poster come from.
  final LibraryApi api;

  /// The list entry that was tapped. Its title is the app-bar title until the
  /// real one arrives, so the screen is never nameless.
  final MediaSummary item;

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

  final _posterToken = CancelToken();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _posterToken.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
          _Files(files: detail.files),
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

/// The item's files.
class _Files extends StatelessWidget {
  const _Files({required this.files});

  final List<FileInfo> files;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Files', style: Theme.of(context).textTheme.titleSmall),
          for (final file in files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(fileLabel(file)),
              // `path` is displayed AS-IS or not at all. It is relative to the
              // server's data directory (M2's finding C3), so joining it with
              // anything — a base URL, a local directory — produces a path
              // that addresses nothing and looks like it should.
              subtitle: file.path.isEmpty ? null : Text(file.path),
              trailing: Text(humanSize(file.size)),
            ),
        ],
      ),
    );
  }
}

/// How one file is named in the list.
///
/// `season` and `episode` are **0 for a single-file item** (SPEC.md §3.3), not
/// absent — so a row that always printed "S0E0" would put a season number on
/// every film in the library.
String fileLabel(FileInfo file) {
  final ext = file.ext.isEmpty ? '' : ' (${file.ext})';
  if (file.season == 0 && file.episode == 0) {
    return file.name.isEmpty
        ? 'File ${file.index.value}$ext'
        : '${file.name}$ext';
  }
  return 'S${file.season}E${file.episode}$ext';
}

/// A byte count a person can read.
///
/// `size` is the only bandwidth signal the API gives (SPEC.md §3.3), so it is
/// worth showing rather than hiding — F13's metered guard is built on the same
/// number at M4.
String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['kB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var unit = 0;
  for (var step = 0; step < units.length - 1; step += 1) {
    if (value < 1024) break;
    value /= 1024;
    unit += 1;
  }
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}
