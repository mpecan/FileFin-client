import 'package:filefin_core/filefin_core.dart';
import 'package:flutter/material.dart';

/// The item's files, and the two labels a row is built from.
///
/// Extracted from `media_detail_page.dart` at M6.4 rather than left in place:
/// that file was 414 lines against `file-size`'s 400-line soft warning and F10
/// adds to it, and a gate warning may fall or hold and never rise. The split
/// is by subject — a file row knows nothing about watch state — so `jscpd` has
/// nothing to find and the two halves stay readable.
///
/// **`path` is displayed AS-IS or not at all.** It is relative to the server's
/// data directory (M2's finding C3), so joining it with anything — a base URL,
/// a local directory — produces a path that addresses nothing and looks like
/// it should.
class FileList extends StatelessWidget {
  /// Lists [files]; [onPlay] starts one, or null when playback is unavailable.
  const FileList({required this.files, this.onPlay, super.key});

  /// The item's files, in the order the server listed them.
  final List<FileInfo> files;

  /// Starts one file, or null when this screen cannot play.
  final void Function(FileIndex file)? onPlay;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final file in files)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(fileLabel(file)),
              subtitle: file.path.isEmpty ? null : Text(file.path),
              trailing: Text(
                file.ext.isEmpty
                    ? humanSize(file.size)
                    : '${humanSize(file.size)} · ${file.ext}',
              ),
              onTap: onPlay == null ? null : () => onPlay!(file.index),
            ),
        ],
      ),
    );
  }
}

/// How one file is named, in this list and in the episode list above it.
///
/// `season` and `episode` are **0 for a single-file item** (SPEC.md §3.3), not
/// absent — so a row that always printed "S0E0" would put a season number on
/// every film in the library.
///
/// **The extension is no longer appended here.** Both call sites now print it
/// separately — the episode row in its own mono facts line, this list in its
/// trailing column — and a label carrying it as well said `.mkv` twice on the
/// same row.
String fileLabel(FileInfo file) {
  if (file.season == 0 && file.episode == 0) {
    return file.name.isEmpty ? 'File ${file.index.value}' : file.name;
  }
  return 'S${file.season}E${file.episode}';
}

/// A byte count a person can read.
///
/// `size` is the only bandwidth signal the API gives (SPEC.md §3.3), so it is
/// worth showing rather than hiding — F13's metered guard is built on the same
/// number at M4.
///
/// **Powers of 1000, ONE constant, because the labels say kB/MB/GB.** Dividing
/// by 1024 under those labels understated every size by 2.4% per step, and
/// `PlaybackPrefs`' own default came out of the dropdown as "477 MB" — an
/// option nobody chose, offered as if they had. The thresholds are written in
/// powers of 1000, so decimal is the base the values are already in. One
/// constant, so the two divisions cannot disagree.
String humanSize(int bytes) {
  const perUnit = 1000;
  if (bytes < perUnit) return '$bytes B';
  const units = ['kB', 'MB', 'GB', 'TB'];
  var value = bytes / perUnit;
  var unit = 0;
  for (var step = 0; step < units.length - 1; step += 1) {
    if (value < perUnit) break;
    value /= perUnit;
    unit += 1;
  }
  return '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}
