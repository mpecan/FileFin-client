/// The two builders both resume test files need.
///
/// Shared rather than repeated: two copies of the same 18 lines is what the
/// duplication gate exists to notice, and a helper that drifts between two
/// files is worse than one that lives in one place.
library;

import 'package:filefin_core/filefin_core.dart';

/// A report on file [file] at [position] seconds of a [duration]-second file.
ProgressReport at(int file, double position, double duration) => ProgressReport(
  file: FileIndex(file),
  position: position,
  duration: duration,
);

/// A state whose pointer sits at [index] with [seconds] elapsed.
WatchState pointing(int index, int seconds, {bool watched = false}) =>
    WatchState(
      pointer: ResumePointer(file: FileIndex(index), seconds: seconds),
      watched: watched,
    );
