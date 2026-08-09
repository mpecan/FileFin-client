/// `applyWatchState` — the fold F10 makes after a watch-state write.
///
/// Every case starts from a **captured** payload rather than a literal: the
/// show fixture is a two-file item the server reported as `watched: true`,
/// `continueIndex: 1`, with both file rows watched, so folding an *unwatched*
/// state onto it has to move all four of those and a fold that missed one
/// cannot pass by leaving it alone.
library;

import 'package:filefin_core/filefin_core.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

MediaDetail _show() =>
    MediaDetail.fromJson(loadFixture('media_detail_multifile_advanced'));

WatchState _at(int file, int seconds) => WatchState(
  pointer: ResumePointer(file: FileIndex(file), seconds: seconds),
);

/// (pointerIndex, pointerSeconds, watched, favorite, rating).
///
/// `pointerIndex` of -1 means no pointer and a value at or above the file count
/// is one nothing resolves — the client-side shape of the server's stale ref.
/// Ratings are drawn inside `0..10` because that is the range every mutator in
/// this library produces; the out-of-range case is `WatchState.fromDetail`'s
/// and has its own example below.
typedef _State = (int, int, bool, bool, int);

final Arbitrary<_State> _states = combine5(
  integer(min: -1, max: 4),
  integer(min: 0, max: 300),
  boolean(),
  boolean(),
  integer(min: 0, max: 10),
);

WatchState _stateOf(_State s) => WatchState(
  pointer: s.$1 < 0
      ? null
      : ResumePointer(file: FileIndex(s.$1), seconds: s.$2),
  watched: s.$3,
  favorite: s.$4,
  rating: s.$5,
);

void main() {
  final base = _show();

  group('applyWatchState — the four fields, and the file rows with them', () {
    test('the file rows move too, and they are what the page was dropping', () {
      // THE case this function exists for. `media_detail_page.dart` folded
      // `watched`, `continueIndex` and `continueSeconds` and left every
      // `files[i].watched` carrying whatever the last fetch said — invisible
      // while nothing drew them, wrong the moment something did. The pointer
      // is at file 1, so file 0 is behind it and reads watched while file 1,
      // the one you are inside, does not.
      final folded = applyWatchState(base, _at(1, 45));
      expect(folded.files.map((f) => f.watched).toList(), [true, false]);
      expect(folded.watched, isFalse);
      expect(folded.continueIndex, 1);
      expect(folded.continueSeconds, 45);
    });

    test('a watched item reads every file watched, wherever the pointer', () {
      final folded = applyWatchState(
        base,
        _at(0, 5).copyWith(watched: true),
      );
      expect(folded.files.map((f) => f.watched).toList(), [true, true]);
      expect(folded.watched, isTrue);
    });

    test('no pointer leaves no file watched and the view at 0/0', () {
      final folded = applyWatchState(base, const WatchState());
      expect(folded.files.map((f) => f.watched).toList(), [false, false]);
      expect(folded.continueIndex, 0);
      expect(folded.continueSeconds, 0);
    });

    test('a pointer past the end reads exactly as no pointer', () {
      // The stale-ref case `resume_vectors.json` exists for: the seconds are
      // real and the index resolves to nothing, and upstream's `View` reports
      // 0/0 with every file unwatched rather than the pointer's own numbers.
      final folded = applyWatchState(base, _at(7, 45));
      expect(folded.continueIndex, 0);
      expect(folded.continueSeconds, 0);
      expect(folded.files.map((f) => f.watched).toList(), [false, false]);
    });

    test('favorite and rating are carried across verbatim', () {
      final folded = applyWatchState(
        base,
        const WatchState(favorite: true, rating: 9),
      );
      expect(folded.favorite, isTrue);
      expect(folded.rating, 9);
    });

    test('a cleared rating really clears — 0 is upstream\'s "unrated"', () {
      final rated = applyWatchState(
        base,
        const WatchState(favorite: true, rating: 8),
      );
      final cleared = applyWatchState(
        rated,
        const WatchState(favorite: true),
      );
      expect(rated.rating, 8);
      expect(cleared.rating, 0);
    });

    test('nothing else on the payload is touched', () {
      final folded = applyWatchState(base, _at(1, 45));
      expect(folded.id, base.id);
      expect(folded.title, base.title);
      expect(folded.year, base.year);
      expect(folded.description, base.description);
      expect(folded.plot, base.plot);
      expect(folded.genres, base.genres);
      expect(folded.metadata, base.metadata);
      expect(
        folded.files.map((f) => (f.index, f.name, f.size, f.transcode)),
        base.files.map((f) => (f.index, f.name, f.size, f.transcode)),
      );
    });

    test('an item with no files folds without reaching for a file row', () {
      final empty = base.copyWith(files: const []);
      final folded = applyWatchState(empty, _at(0, 30));
      expect(folded.files, isEmpty);
      expect(folded.continueIndex, 0);
      expect(folded.continueSeconds, 0);
    });

    test(
      'an UNRELATED write leaves a server rating of 99 exactly where it was',
      () {
        // M6.R/P1.4, and the case that was missing. The server validates a
        // rating on write and not on read (M6.0/E-6: a hand-edited `meta.json`
        // really does serve 99), and `setFavorite` is a total assignment to
        // `favorite` in the server's own fold — it does not read or change a
        // rating. So the folded payload must still say 99.
        //
        // It said 0, because `WatchState.fromDetail` normalised the rating away
        // and this function writes `state.rating` back. The screen said *Not
        // rated* and dropped the line explaining the value, while the server
        // still held 99. The old case asserted that normalisation and called
        // the fold "applied only after a real mutation" — but a real mutation
        // of *favourite* is exactly what dragged it along.
        final served = base.copyWith(rating: 99);

        final folded = applyWatchState(
          served,
          setFavorite(WatchState.fromDetail(served), favorite: true),
        );

        expect(folded.rating, 99);
        expect(folded.favorite, isTrue);
      },
    );
  });

  group('applyWatchState — properties', () {
    KiriCheck.seed = 20260809;
    KiriCheck.maxExamples = 300;

    property('the fold is a fixed point of the wire round trip', () {
      forAll(_states, (_State s) {
        final once = applyWatchState(base, _stateOf(s));
        final twice = applyWatchState(once, WatchState.fromDetail(once));
        expect(twice, once);
      });
    });

    property('the watched files are always a prefix of the list', () {
      // `perFile[i] = watched || i < ptr`, so the true values can only ever be
      // an unbroken run from the start. A fold that indexed the view wrongly
      // would produce a hole.
      forAll(_states, (_State s) {
        final flags = applyWatchState(
          base,
          _stateOf(s),
        ).files.map((f) => f.watched).toList();
        final watchedCount = flags.where((w) => w).length;
        expect(
          flags,
          [for (var i = 0; i < flags.length; i++) i < watchedCount],
          reason: 'the watched flags were not a prefix: $flags',
        );
      });
    });

    property('it never invents or drops a file, and never renames one', () {
      forAll(_states, (_State s) {
        final folded = applyWatchState(base, _stateOf(s));
        expect(folded.files.length, base.files.length);
        expect(
          folded.files.map((f) => f.name).toList(),
          base.files.map((f) => f.name).toList(),
        );
      });
    });

    property('the folded payload agrees with the engine it came from', () {
      forAll(_states, (_State s) {
        final state = _stateOf(s);
        final view = deriveView(state, fileCount: base.files.length);
        final folded = applyWatchState(base, state);
        expect(folded.watched, view.watched);
        expect(folded.continueIndex, view.continueIndex.value);
        expect(folded.continueSeconds, view.continueSeconds);
        expect(folded.files.map((f) => f.watched).toList(), view.perFile);
      });
    });
  });
}
