/// Property-based tests for the progress reporting policy.
///
/// `progress_policy_test.dart` pins the rules one row at a time. These pin the
/// invariants a whole *sequence* of ticks must satisfy — which is the shape the
/// reporter actually runs in, and the shape a single-decision test cannot see.
///
/// The seed is fixed, for the reason `resume_properties_test.dart` gives:
/// `just mutants` runs `dart test` once per mutant, so a generator drawing a
/// different sample each run would turn a surviving mutant into a coin flip.
library;

import 'package:filefin_core/filefin_core.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

/// One tick: (fileIndex, positionTenths, durationTenths, eventIndex).
///
/// Positions are drawn as tenths so the generator produces exact halves — the
/// rounding boundary — rather than arbitrary binary fractions, and the ranges
/// deliberately include the values rule 1 refuses (a non-positive duration, a
/// negative position).
typedef _Tick = (int, int, int, int);

final Arbitrary<List<_Tick>> _ticks = list(
  combine4(
    integer(min: 0, max: 2),
    integer(min: -50, max: 6000),
    integer(min: -10, max: 1000),
    integer(min: 0, max: ProgressEvent.values.length - 1),
  ),
  minLength: 1,
  maxLength: 25,
);

void main() {
  KiriCheck.seed = 20260808;
  KiriCheck.maxExamples = 300;

  /// Replays a whole tick sequence exactly as `ProgressReporter` will: decide,
  /// and advance `lastSent` **only** when the decision was to send.
  List<(ProgressReport, SentReport?)> replay(
    List<_Tick> ticks, {
    required int intervalSecs,
  }) {
    final sends = <(ProgressReport, SentReport?)>[];
    SentReport? lastSent;
    for (final (file, positionTenths, durationTenths, eventIndex) in ticks) {
      final decision = decideReport(
        file: FileIndex(file),
        position: positionTenths / 10,
        duration: durationTenths / 10,
        event: ProgressEvent.values[eventIndex],
        lastSent: lastSent,
        intervalSecs: intervalSecs,
      );
      if (decision is SendProgress) {
        sends.add((decision.report, lastSent));
        lastSent = SentReport(
          file: decision.report.file,
          positionSeconds: roundReportedSeconds(decision.report.position),
        );
      }
    }
    return sends;
  }

  property(
    'a send always carries the file, position and event it was given',
    () {
      forAll(_ticks, (List<_Tick> ticks) {
        SentReport? lastSent;
        for (final (file, positionTenths, durationTenths, eventIndex)
            in ticks) {
          final position = positionTenths / 10;
          final duration = durationTenths / 10;
          final event = ProgressEvent.values[eventIndex];
          final decision = decideReport(
            file: FileIndex(file),
            position: position,
            duration: duration,
            event: event,
            lastSent: lastSent,
            intervalSecs: 30,
          );
          if (decision is! SendProgress) continue;
          // The single most consequential thing this function can get wrong: a
          // report keyed on the wrong file writes the resume pointer into the
          // wrong episode, and the server has no way to notice.
          expect(decision.report.file, FileIndex(file));
          expect(decision.report.position, position);
          expect(decision.report.duration, duration);
          expect(decision.report.event, event);
          lastSent = SentReport(
            file: decision.report.file,
            positionSeconds: roundReportedSeconds(position),
          );
        }
      });
    },
  );

  property('nothing is ever sent without a usable duration', () {
    forAll(_ticks, (List<_Tick> ticks) {
      for (final (report, _) in replay(ticks, intervalSecs: 30)) {
        expect(report.duration, greaterThan(0));
        expect(report.duration.isFinite, isTrue);
        expect(report.position.isFinite, isTrue);
      }
    });
  });

  property(
    'consecutive checkpoints on one file are at least the interval apart',
    () {
      forAll(_ticks, (List<_Tick> ticks) {
        for (final intervalSecs in [1, 30, 120]) {
          for (final (report, previous) in replay(
            ticks,
            intervalSecs: intervalSecs,
          )) {
            if (report.event.isTerminal) continue;
            if (previous == null || previous.file != report.file) continue;
            expect(
              (roundReportedSeconds(report.position) - previous.positionSeconds)
                  .abs(),
              greaterThanOrEqualTo(intervalSecs),
              reason: 'checkpoint too close to the previous send',
            );
          }
        }
      });
    },
  );

  property('a terminal event never repeats the exact report before it', () {
    forAll(_ticks, (List<_Tick> ticks) {
      for (final (report, previous) in replay(ticks, intervalSecs: 30)) {
        if (!report.event.isTerminal || previous == null) continue;
        final same =
            previous.file == report.file &&
            previous.positionSeconds == roundReportedSeconds(report.position);
        expect(same, isFalse);
      }
    });
  });

  property('the decision is total — every tick answers send or skip', () {
    forAll(_ticks, (List<_Tick> ticks) {
      SentReport? lastSent;
      for (final (file, positionTenths, durationTenths, eventIndex) in ticks) {
        final decision = decideReport(
          file: FileIndex(file),
          position: positionTenths / 10,
          duration: durationTenths / 10,
          event: ProgressEvent.values[eventIndex],
          lastSent: lastSent,
          intervalSecs: 30,
        );
        final described = switch (decision) {
          SendProgress() => 'send',
          SkipProgress() => 'skip',
        };
        expect(described, anyOf('send', 'skip'));
        if (decision is SendProgress) {
          lastSent = SentReport(
            file: decision.report.file,
            positionSeconds: roundReportedSeconds(decision.report.position),
          );
        }
      }
    });
  });
}
