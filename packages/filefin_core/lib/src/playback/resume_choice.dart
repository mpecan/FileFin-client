import 'package:filefin_core/src/ids.dart';
import 'package:filefin_core/src/models/media_detail.dart';
import 'package:filefin_core/src/resume/engine.dart';
import 'package:filefin_core/src/resume/watch_state.dart';

/// Whether F8 has a resume position to offer, and what it is.
sealed class ResumeChoice {
  /// Allows the const subclasses below.
  const ResumeChoice();
}

/// There is somewhere to resume from: [file], [seconds] into it.
final class ResumeAvailable extends ResumeChoice {
  /// Resume [file] at [seconds].
  const ResumeAvailable({required this.file, required this.seconds});

  /// The file the pointer resolves to.
  final FileIndex file;

  /// How many whole seconds into it.
  final int seconds;
}

/// Nothing to resume: a fresh item, a watched one, or a pointer that no longer
/// resolves.
final class NoResume extends ResumeChoice {
  /// Start at the beginning.
  const NoResume();
}

/// F8's whole policy: does this item offer *Resume* as well as *Play*?
///
/// **This is upstream's own rule, observed rather than invented.** Its player
/// computes `hasResume = !watched &&
/// (continueIndex > 0 || continueSeconds > 0)`
/// (`web/src/lib/app.svelte.js:423`), and that is what resolves the `(0, 0)`
/// ambiguity M1 recorded and could not close from the payload alone: a view of
/// `(0, 0)` is reported both for an item nobody has played and for a pointer
/// whose ref no longer matches any file, and the two are indistinguishable on
/// the wire. Neither is offered, so this client never seeks to a position it
/// made up.
///
/// The detail goes through the engine — `WatchState.fromDetail` then
/// [deriveView] — rather than being read field by field, which is what makes a
/// `continueIndex` past the end of the file list normalise to *no resume*
/// instead of an offer to seek into a file that is not there. That is the stale
/// pointer case `test/fixtures/resume_vectors.json` exists for, and reproducing
/// its resolution here rather than re-deriving it is the point.
ResumeChoice offerResume(MediaDetail detail) {
  final view = deriveView(
    WatchState.fromDetail(detail),
    fileCount: detail.files.length,
  );
  if (view.watched) return const NoResume();
  if (view.continueIndex.value > 0 || view.continueSeconds > 0) {
    return ResumeAvailable(
      file: view.continueIndex,
      seconds: view.continueSeconds,
    );
  }
  return const NoResume();
}

/// Where playback of [picked] should start, in whole seconds.
///
/// Upstream's `playFile(idx)` seeks only when `idx == continueIndex`
/// (`web/src/lib/app.svelte.js:864`). So tapping episode 1 after leaving off
/// halfway through episode 2 starts episode 1 at the beginning — which is what
/// the person who tapped that row asked for, and what every other client of
/// this server does.
///
/// Written in terms of [offerResume] rather than beside it, so the two can
/// never disagree about whether a pointer resolves.
int startSecondsFor(MediaDetail detail, FileIndex picked) =>
    switch (offerResume(detail)) {
      ResumeAvailable(:final file, :final seconds) when file == picked =>
        seconds,
      _ => 0,
    };
