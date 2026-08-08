/// Example-based tests for `applyProgress` — one group per rule in
/// `docs/server-api.md`'s "Resume semantics", itself a transcription of
/// `internal/state/engine.go`.
///
/// The captured vectors in `resume_vectors_test.dart` check agreement with the
/// real engine on 601 inputs; these say which rule each behaviour comes from,
/// so a failure names the rule rather than a vector id.
library;

import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/resume_builders.dart';

/// The seconds `applyProgress` records for a report at [position] on a
/// two-file item's first file, where no crossing and no clamping intervene.
int _secondsAfter(double position) => applyProgress(
  const WatchState(),
  at(0, position, 1000000000),
  fileCount: 2,
).pointer!.seconds;

void main() {
  group('rule 1 — out of range is identity', () {
    test('a negative or too-large file index changes nothing at all', () {
      final start = pointing(1, 45, watched: true).copyWith(
        favorite: true,
        rating: 7,
      );
      for (final file in [-1, -99, 3, 99]) {
        expect(
          applyProgress(start, at(file, 95, 100), fileCount: 3),
          start,
          reason: 'file $file',
        );
      }
    });

    test(
      'watched is included in "unchanged" — a crossing does not leak out',
      () {
        const start = WatchState();
        expect(
          applyProgress(start, at(5, 100, 100), fileCount: 2).watched,
          isFalse,
        );
      },
    );

    test('fileCount 0 leaves every index out of range', () {
      const start = WatchState();
      expect(applyProgress(start, at(0, 50, 100), fileCount: 0), start);
    });
  });

  group('rule 2 — crossing', () {
    test('exactly 0.90 crosses: the comparison is >=, not >', () {
      expect(
        applyProgress(
          const WatchState(),
          at(0, 90, 100),
          fileCount: 1,
        ).watched,
        isTrue,
      );
      expect(
        applyProgress(
          const WatchState(),
          at(0, 89.9, 100),
          fileCount: 1,
        ).watched,
        isFalse,
      );
    });

    test('duration <= 0 is never crossed, whatever the position', () {
      for (final duration in [0.0, -1.0, -100.0]) {
        final out = applyProgress(
          const WatchState(),
          at(0, 1000, duration),
          fileCount: 1,
        );
        expect(out.watched, isFalse, reason: 'duration $duration');
      }
    });

    test('a huge position over a zero duration still does not cross', () {
      expect(
        applyProgress(
          const WatchState(),
          at(0, 1000000000, 0),
          fileCount: 2,
        ).pointer,
        const ResumePointer(file: FileIndex(0), seconds: 1000000000),
      );
    });
  });

  group('rule 3 — where the pointer is aimed', () {
    test('not crossed: at the reported file, at the rounded position', () {
      final out = applyProgress(
        const WatchState(),
        at(1, 50.4, 100),
        fileCount: 3,
      );
      expect(out.pointer, const ResumePointer(file: FileIndex(1), seconds: 50));
      expect(out.watched, isFalse);
    });

    test('crossing a non-last file aims at the NEXT file, at 0 seconds', () {
      final out = applyProgress(
        const WatchState(),
        at(0, 95, 100),
        fileCount: 3,
      );
      expect(out.pointer, const ResumePointer(file: FileIndex(1), seconds: 0));
      expect(out.watched, isFalse);
    });

    test('crossing the last file sets watched and stays on that file', () {
      final out = applyProgress(
        const WatchState(),
        at(2, 95, 100),
        fileCount: 3,
      );
      expect(out.watched, isTrue);
      expect(out.pointer, const ResumePointer(file: FileIndex(2), seconds: 95));
    });

    test('a single-file item is its own last file', () {
      final out = applyProgress(
        const WatchState(),
        at(0, 95, 100),
        fileCount: 1,
      );
      expect(out.watched, isTrue);
      expect(out.pointer, const ResumePointer(file: FileIndex(0), seconds: 95));
    });
  });

  group("rule 4 — rounding is Go's int(x + 0.5), not Dart's .round()", () {
    test('halves go up', () {
      expect(_secondsAfter(1.4), 1);
      expect(_secondsAfter(1.5), 2);
      expect(_secondsAfter(1.6), 2);
      expect(_secondsAfter(2.5), 3);
    });

    test('a negative position clamps to 0 rather than rounding', () {
      // This is where .round() diverges: (-0.5).round() is -1 in Dart and 0
      // through Go's clamp, and -0.5 is reachable from a seek to the start.
      expect(_secondsAfter(-0.5), 0);
      expect(_secondsAfter(-1.6), 0);
      expect(_secondsAfter(-0.4), 0);
    });

    test('non-finite positions are clamped, which upstream does not do', () {
      // Client hardening, not a claim about the server: Dart's .toInt() throws
      // on NaN and Infinity where Go's int() does not.
      expect(_secondsAfter(double.nan), 0);
      expect(_secondsAfter(double.infinity), 0);
      expect(_secondsAfter(double.negativeInfinity), 0);
    });

    test('a NaN duration never crosses', () {
      final out = applyProgress(
        const WatchState(),
        at(0, 50, double.nan),
        fileCount: 1,
      );
      expect(out.watched, isFalse);
    });
  });

  group('rule 5 — an absent pointer reads as index -1', () {
    test('the first report on file 0 always installs a pointer', () {
      final out = applyProgress(
        const WatchState(),
        at(0, 0, 100),
        fileCount: 3,
      );
      expect(out.pointer, const ResumePointer(file: FileIndex(0), seconds: 0));
    });

    test('a pointer whose index is out of range reads as -1 too', () {
      // The index-space equivalent of the server's stale ref: a file list that
      // shrank between sessions leaves a pointer nothing resolves.
      final out = applyProgress(
        pointing(9, 45),
        at(0, 10, 100),
        fileCount: 3,
      );
      expect(out.pointer, const ResumePointer(file: FileIndex(0), seconds: 10));
    });
  });

  group('rule 6 — the pointer only moves forward', () {
    test('a later file always wins', () {
      final out = applyProgress(pointing(0, 90), at(2, 5, 100), fileCount: 3);
      expect(out.pointer, const ResumePointer(file: FileIndex(2), seconds: 5));
    });

    test('rewatching an earlier file does not regress it', () {
      final start = pointing(2, 10);
      expect(
        applyProgress(start, at(0, 99, 100), fileCount: 3).pointer,
        start.pointer,
      );
      expect(
        applyProgress(start, at(1, 50, 100), fileCount: 3).pointer,
        start.pointer,
      );
    });

    test('the same file advances only forwards in seconds', () {
      final start = pointing(1, 45);
      expect(
        applyProgress(start, at(1, 60, 100), fileCount: 3).pointer,
        const ResumePointer(file: FileIndex(1), seconds: 60),
      );
      expect(
        applyProgress(start, at(1, 30, 100), fileCount: 3).pointer,
        start.pointer,
      );
      expect(
        applyProgress(start, at(1, 45, 100), fileCount: 3).pointer,
        start.pointer,
      );
    });
  });

  group('rule 7 — the last-file asymmetry', () {
    test(
      'crossing the last file sets watched but does NOT advance the seconds',
      () {
        // Captured: pointer at 45s, report 95 of 100. `watched` becomes
        // true; the pointer keeps 45, because the equal-index branch requires
        // !crossed. Only an absent pointer at that index writes 95.
        final start = pointing(2, 45);
        final out = applyProgress(start, at(2, 95, 100), fileCount: 3);
        expect(out.watched, isTrue);
        expect(
          out.pointer,
          const ResumePointer(file: FileIndex(2), seconds: 45),
        );
      },
    );

    test('with no pointer at that index, the same report writes 95', () {
      final out = applyProgress(
        pointing(1, 45),
        at(2, 95, 100),
        fileCount: 3,
      );
      expect(out.watched, isTrue);
      expect(out.pointer, const ResumePointer(file: FileIndex(2), seconds: 95));
    });

    test('a non-last crossing is not asymmetric — it moves on regardless', () {
      final out = applyProgress(
        pointing(1, 45),
        at(1, 95, 100),
        fileCount: 3,
      );
      expect(out.watched, isFalse);
      expect(out.pointer, const ResumePointer(file: FileIndex(2), seconds: 0));
    });
  });
}
