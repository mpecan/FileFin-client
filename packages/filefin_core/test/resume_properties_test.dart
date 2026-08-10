/// Property-based tests for the resume engine.
///
/// The example tests pin the rules and the captured vectors pin agreement with
/// the server on 601 specific inputs. These pin the invariants that must hold
/// across *all* inputs — the ones a grid can only sample.
///
/// The seed is fixed. `just mutants` runs `dart test` once per mutant, so a
/// generator that draws a different sample each run would turn a surviving
/// mutant into a coin flip and the gate into a flaky one.
///
/// This is not glados, which the plan named: every published glados version
/// declares `sdk: >=2.12.0 <3.0.0` and cannot resolve on Dart 3.
library;

import 'package:filefin_core/filefin_core.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

/// (fileCount, pointerIndex, pointerSeconds, watched, reportFile,
/// positionTenths, durationTenths).
///
/// `pointerIndex` of -1 means no pointer; a value at or above `fileCount` is a
/// pointer nothing resolves — the client-side shape of the server's stale ref.
/// Position and duration are drawn as tenths so the generator produces exact
/// halves (the rounding boundary) rather than arbitrary binary fractions.
typedef _Scenario = (int, int, int, bool, int, int, int);

final Arbitrary<_Scenario> _scenarios = combine7(
  integer(min: 1, max: 5),
  integer(min: -1, max: 6),
  integer(min: 0, max: 200),
  boolean(),
  integer(min: -2, max: 7),
  integer(min: -100, max: 2000),
  integer(min: -10, max: 2000),
);

WatchState _stateOf(_Scenario s) => WatchState(
  pointer: s.$2 < 0
      ? null
      : ResumePointer(file: FileIndex(s.$2), seconds: s.$3),
  watched: s.$4,
);

ProgressReport _reportOf(_Scenario s) => ProgressReport(
  file: FileIndex(s.$5),
  position: s.$6 / 10,
  duration: s.$7 / 10,
);

/// The pointer as the engine actually reads it: an unresolvable pointer reads
/// as `(-1, 0)`, which is what an absent one reads as.
(int, int) _resolved(WatchState state, int fileCount) {
  final index = resolveIndex(state.pointer, fileCount);
  return index < 0 ? (-1, 0) : (index, state.pointer!.seconds);
}

bool _notBefore((int, int) after, (int, int) before) =>
    after.$1 > before.$1 || (after.$1 == before.$1 && after.$2 >= before.$2);

void main() {
  KiriCheck.seed = 20260808;
  KiriCheck.maxExamples = 300;

  property('an out-of-range file index changes nothing', () {
    forAll(_scenarios, (_Scenario s) {
      final state = _stateOf(s);
      final fileCount = s.$1;
      if (s.$5 >= 0 && s.$5 < fileCount) return;
      expect(applyProgress(state, _reportOf(s), fileCount: fileCount), state);
    });
  });

  property('the resume pointer never moves backwards', () {
    forAll(_scenarios, (_Scenario s) {
      final fileCount = s.$1;
      final state = _stateOf(s);
      final after = applyProgress(state, _reportOf(s), fileCount: fileCount);
      expect(
        _notBefore(_resolved(after, fileCount), _resolved(state, fileCount)),
        isTrue,
        reason:
            '${_resolved(state, fileCount)} -> '
            '${_resolved(after, fileCount)}',
      );
    });
  });

  property('watched only ever goes from false to true', () {
    forAll(_scenarios, (_Scenario s) {
      final state = _stateOf(s);
      final after = applyProgress(state, _reportOf(s), fileCount: s.$1);
      if (state.watched) expect(after.watched, isTrue);
    });
  });

  property('watched turns on only when the LAST file crosses', () {
    forAll(_scenarios, (_Scenario s) {
      final fileCount = s.$1;
      final state = _stateOf(s);
      final report = _reportOf(s);
      final after = applyProgress(state, report, fileCount: fileCount);
      if (state.watched || !after.watched) return;
      expect(report.file, FileIndex(fileCount - 1));
      expect(report.duration > 0, isTrue);
      expect(report.position / report.duration, greaterThanOrEqualTo(0.90));
    });
  });

  property(
    'applying the same report twice changes nothing the second time',
    () {
      forAll(_scenarios, (_Scenario s) {
        final report = _reportOf(s);
        final once = applyProgress(_stateOf(s), report, fileCount: s.$1);
        expect(applyProgress(once, report, fileCount: s.$1), once);
      });
    },
  );

  property('the derived view is always addressable', () {
    forAll(_scenarios, (_Scenario s) {
      final fileCount = s.$1;
      final after = applyProgress(
        _stateOf(s),
        _reportOf(s),
        fileCount: fileCount,
      );
      final view = deriveView(after, fileCount: fileCount);
      expect(view.perFile, hasLength(fileCount));
      expect(view.continueIndex.value, inInclusiveRange(0, fileCount - 1));
      expect(view.continueSeconds, greaterThanOrEqualTo(0));
    });
  });

  property('the view agrees with the resolved pointer, never the raw one', () {
    forAll(_scenarios, (_Scenario s) {
      final fileCount = s.$1;
      final state = _stateOf(s);
      final view = deriveView(state, fileCount: fileCount);
      final (index, seconds) = _resolved(state, fileCount);
      expect(view.continueIndex, FileIndex(index < 0 ? 0 : index));
      expect(view.continueSeconds, seconds);
      for (var i = 0; i < fileCount; i++) {
        expect(view.perFile[i], state.watched || i < index, reason: 'file $i');
      }
    });
  });

  property('clearWatched absorbs — everything it clears stays cleared', () {
    forAll(_scenarios, (_Scenario s) {
      final cleared = clearWatched(_stateOf(s));
      expect(cleared.watched, isFalse);
      expect(cleared.pointer, isNull);
      expect(clearWatched(cleared), cleared);
    });
  });

  property('setWatched and setFavorite never touch the pointer or rating', () {
    forAll(_scenarios, (_Scenario s) {
      final state = _stateOf(s).copyWith(rating: 7);
      for (final flag in [true, false]) {
        expect(setWatched(state, watched: flag).pointer, state.pointer);
        expect(setWatched(state, watched: flag).rating, 7);
        expect(setFavorite(state, favorite: flag).pointer, state.pointer);
        expect(setFavorite(state, favorite: flag).watched, state.watched);
      }
    });
  });

  property('a valid rating is stored verbatim and nothing else moves', () {
    forAll(combine2(_scenarios, integer(min: 0, max: 10)), (
      (_Scenario, int) pair,
    ) {
      final state = _stateOf(pair.$1);
      final rated = setRating(state, rating: pair.$2);
      expect(rated.rating, pair.$2);
      expect(rated.pointer, state.pointer);
      expect(rated.watched, state.watched);
      expect(rated.favorite, state.favorite);
    });
  });
}
