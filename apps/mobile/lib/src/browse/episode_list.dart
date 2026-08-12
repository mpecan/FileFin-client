import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/file_list.dart'
    show fileLabel, humanSize;
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';

/// The item's files, grouped into seasons and put above the description.
///
/// **The design's episode thumbnails are not drawn, because none exist.** Every
/// episode row in `FileFin Redesign.dc.html` carries an 88×50 still; this
/// server serves one image per *item* and none per file (`docs/server-api.md`),
/// so a column of them would be a column of identical placeholders. The row is
/// the design's otherwise: its height, its code-then-metadata pairing, and the
/// play glyph on the right.
///
/// **A season tab appears only when the files actually carry seasons.**
/// `season` and `episode` are **0 for a single-file item** (SPEC.md §3.3), not
/// absent, so a film would otherwise get a tab called "Season 0".
class EpisodeList extends StatefulWidget {
  /// Lists [files]; [onPlay] starts one, or null when playback is unavailable.
  const EpisodeList({required this.files, this.onPlay, super.key});

  /// The item's files, in the order the server listed them.
  final List<FileInfo> files;

  /// Starts one file, or null when this screen cannot play.
  final void Function(FileIndex file)? onPlay;

  @override
  State<EpisodeList> createState() => _EpisodeListState();
}

class _EpisodeListState extends State<EpisodeList> {
  int? _season;

  /// Every season present, ascending. Empty when the files carry none.
  List<int> get _seasons =>
      widget.files.map((f) => f.season).where((s) => s > 0).toSet().toList()
        ..sort();

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) return const SizedBox.shrink();
    final palette = FileFinPalette.of(context);
    final seasons = _seasons;
    // The stored season is checked against what is present rather than trusted:
    // the detail is refetched after a write, and a file list that changed under
    // a chosen season would otherwise show an empty list with no way back.
    final chosen = seasons.contains(_season) ? _season : seasons.firstOrNull;
    final shown = chosen == null
        ? widget.files
        : [
            for (final file in widget.files)
              if (file.season == chosen) file,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (seasons.length > 1)
          _SeasonTabs(
            seasons: seasons,
            chosen: chosen!,
            count: shown.length,
            palette: palette,
            onPick: (season) => setState(() => _season = season),
          ),
        for (final file in shown)
          _EpisodeRow(
            file: file,
            palette: palette,
            onPlay: widget.onPlay == null
                ? null
                : () => widget.onPlay!(file.index),
          ),
      ],
    );
  }
}

class _SeasonTabs extends StatelessWidget {
  const _SeasonTabs({
    required this.seasons,
    required this.chosen,
    required this.count,
    required this.palette,
    required this.onPick,
  });

  final List<int> seasons;
  final int chosen;
  final int count;
  final FileFinPalette palette;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
    child: Row(
      children: [
        Expanded(
          child: SizedBox(
            // 48 rather than the design's 30: the pill inside stays 30 and the
            // tap target around it satisfies `androidTapTargetGuideline`.
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) => _SeasonPill(
                season: seasons[index],
                selected: seasons[index] == chosen,
                palette: palette,
                onTap: () => onPick(seasons[index]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          count == 1 ? '1 ep' : '$count eps',
          style: mono(size: 11, color: palette.textFaint),
        ),
      ],
    ),
  );
}

class _SeasonPill extends StatelessWidget {
  const _SeasonPill({
    required this.season,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final int season;
  final bool selected;
  final FileFinPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      alignment: Alignment.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? palette.accentFill : Colors.transparent,
          border: Border.all(
            color: selected ? palette.accentBright : palette.outline,
          ),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          'Season $season',
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            color: selected ? palette.accentSoft : palette.textMuted,
          ),
        ),
      ),
    ),
  );
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.file,
    required this.palette,
    required this.onPlay,
  });

  final FileInfo file;
  final FileFinPalette palette;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPlay,
    child: Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileLabel(file),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  episodeFacts(file),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(size: 11, color: palette.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            file.watched ? Icons.check_circle : Icons.play_circle_outline,
            size: 22,
            color: file.watched ? palette.textFaint : palette.accentBright,
          ),
        ],
      ),
    ),
  );
}

/// The mono line under an episode's name: size and container.
///
/// **`transcode` is on it, and it is the most useful thing there.** It is the
/// server's own verdict on whether this file will be remuxed to HLS before it
/// reaches the player (`internal/server/playback.go:78`), which is what decides
/// whether playback starts instantly or after a transcode — and F12 exists
/// because a user can have that path turned off entirely.
///
/// Public only so a test can reach it; nothing outside this library calls it
/// (§5, `public_member_no_consumer`).
@visibleForTesting
String episodeFacts(FileInfo file) => [
  if (file.size > 0) humanSize(file.size),
  if (file.ext.isNotEmpty) file.ext.replaceFirst('.', ''),
  if (file.transcode) 'transcode',
].join(' · ');
