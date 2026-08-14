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
/// **Upstream's own rule, observed rather than invented**: its player computes
/// `hasResume = !watched && (continueIndex > 0 || continueSeconds > 0)`
/// (`web/src/lib/app.svelte.js:423`). That is also what settles D15's `(0, 0)`
/// ambiguity — neither an unplayed item nor a stale pointer is offered, so this
/// client never seeks to a position it made up.
///
/// It goes through the engine rather than reading fields, which is what
/// normalises a `continueIndex` past the end of the file list to *no resume*
/// rather than an offer to seek into a file that is not there.
/// `test/fixtures/resume_vectors.json` is the oracle for that case.
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
/// (`web/src/lib/app.svelte.js:864`), so tapping episode 1 after leaving off in
/// episode 2 starts episode 1 at the beginning. Written in terms of
/// [offerResume] so the two cannot disagree about whether a pointer resolves.
///
/// **No default arm, which is the point of the second `ResumeAvailable()`
/// case**: the first arm is *guarded*, and a guarded pattern cannot make a
/// switch exhaustive on its own. With `_ => 0` a new [ResumeChoice] variant
/// silently started every file at 0; with the arms below it is a compile error
/// (measured both directions, M6.1).
int startSecondsFor(MediaDetail detail, FileIndex picked) =>
    switch (offerResume(detail)) {
      ResumeAvailable(:final file, :final seconds) when file == picked =>
        seconds,
      ResumeAvailable() => 0,
      NoResume() => 0,
    };
