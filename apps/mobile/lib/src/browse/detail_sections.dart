import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/file_list.dart';
import 'package:filefin_mobile/src/browse/watch_actions.dart';
import 'package:filefin_mobile/src/browse/watch_state_controls.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';

/// The two disclosure rows the design puts under the episode list.
///
/// **Collapsed by default is the whole point of the redesign's detail page.**
/// The old screen led with a poster and eleven metadata blocks and put the
/// episode a person came for below all of it. Everything descriptive now sits
/// behind one row each, so the fold holds the title, how to resume it, and what
/// to play.
class DetailSections extends StatelessWidget {
  /// Draws [detail]'s prose and files, writing a rating through [actions].
  const DetailSections({
    required this.detail,
    required this.actions,
    super.key,
  });

  /// The item.
  final MediaDetail detail;

  /// Where the rating writes to.
  final WatchActions actions;

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return Column(
      children: [
        _Section(
          title: 'Description & cast',
          palette: palette,
          children: [
            if (detail.description.isNotEmpty) Text(detail.description),
            // `plot` is a second, usually longer prose field; when the server
            // has filled both with the same words, saying them twice is worse
            // than saying them once.
            if (detail.plot.isNotEmpty && detail.plot != detail.description)
              Text(detail.plot),
            _Chips(label: 'Genres', values: detail.genres),
            _Chips(label: 'Tags', values: detail.tags),
            _Chips(label: 'Cast', values: detail.actors),
            _Pairs(label: 'Details', pairs: detail.metadata),
            _Pairs(label: 'Ratings', pairs: detail.ratings),
            RatingField(detail: detail, actions: actions),
          ],
        ),
        // Absent, not empty, when the server sent neither: a disclosure row
        // reading "Files & technical 0" invites a tap that opens nothing, and
        // an un-enriched item with no file list is the ordinary case rather
        // than a fault.
        if (detail.files.isNotEmpty || detail.technical.isNotEmpty)
          _Section(
            title: 'Files & technical',
            trailing: filesSummary(detail),
            palette: palette,
            children: [
              FileList(files: detail.files),
              _Pairs(label: 'Technical', pairs: detail.technical),
            ],
          ),
      ],
    );
  }
}

/// The mono count on the *Files & technical* row: how many, and of what.
///
/// The design writes it `12 · avi`. The extension is the first one present
/// rather than a list, because a single item's files are one recording split
/// into parts and share a container in every payload captured so far; when they
/// do not, the count is still true and the extension is still the one a player
/// will open first.
///
@visibleForTesting
String filesSummary(MediaDetail detail) {
  final extension = detail.files
      .map((file) => file.ext.replaceFirst('.', ''))
      .where((ext) => ext.isNotEmpty)
      .firstOrNull;
  return [
    '${detail.files.length}',
    if (extension != null) extension,
  ].join(' · ');
}

/// One collapsible row, and what it hides.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.palette,
    required this.children,
    this.trailing,
  });

  final String title;
  final String? trailing;
  final FileFinPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Theme(
    // A `Theme`, not a `copyWith` per property: `ExpansionTile` draws its own
    // dividers from `dividerColor`, and the design has none above or below the
    // row — the row's own hairline is the rule.
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: ExpansionTile(
        title: Text(
          title,
          style: TextStyle(fontSize: 13, color: palette.textMuted),
        ),
        trailing: trailing == null
            ? null
            : Text(
                trailing!,
                style: mono(size: 11, color: palette.textFaint),
              ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
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
/// (`media.go,93`): a listed key gets a friendly label and everything else
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
