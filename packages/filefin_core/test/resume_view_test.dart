/// Example-based tests for everything in the resume engine that is not
/// `applyProgress`: `deriveView`, `WatchState.fromDetail`, and the five
/// single-purpose mutations the six watch-state routes map onto.
library;

import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/resume_builders.dart';

void main() {
  group('deriveView', () {
    test('no pointer reads as index 0, second 0, nothing watched', () {
      final view = deriveView(const WatchState(), fileCount: 3);
      expect(view.watched, isFalse);
      expect(view.continueIndex, const FileIndex(0));
      expect(view.continueSeconds, 0);
      expect(view.perFile, [false, false, false]);
    });

    test('a pointer whose index is out of range reads identically to none', () {
      // The whole point of resolving the pointer ONCE. `continueSeconds =
      // pointer?.seconds ?? 0` would report 45 here, and it is wrong.
      final view = deriveView(pointing(9, 45), fileCount: 3);
      expect(view.continueIndex, const FileIndex(0));
      expect(view.continueSeconds, 0);
      expect(view.perFile, [false, false, false]);
    });

    test(
      'the file AT the pointer is not watched — you are in the middle of it',
      () {
        final view = deriveView(pointing(1, 30), fileCount: 3);
        expect(view.continueIndex, const FileIndex(1));
        expect(view.continueSeconds, 30);
        expect(view.perFile, [true, false, false]);
      },
    );

    test('the folder flag makes every file read watched, pointer or not', () {
      expect(
        deriveView(pointing(0, 5, watched: true), fileCount: 3).perFile,
        [true, true, true],
      );
      expect(
        deriveView(const WatchState(watched: true), fileCount: 2).perFile,
        [true, true],
      );
    });

    test('perFile is exactly as long as the file list', () {
      expect(deriveView(const WatchState(), fileCount: 0).perFile, isEmpty);
      expect(
        deriveView(const WatchState(), fileCount: 1).perFile,
        hasLength(1),
      );
      expect(deriveView(pointing(4, 1), fileCount: 5).perFile, [
        true,
        true,
        true,
        true,
        false,
      ]);
    });
  });

  group('WatchState.fromDetail', () {
    test('reads the derived view off a captured detail payload', () {
      final advanced = WatchState.fromDetail(
        MediaDetail.fromJson(loadFixture('media_detail_multifile_advanced')),
      );
      expect(advanced.watched, isTrue);
      expect(
        advanced.pointer,
        const ResumePointer(file: FileIndex(1), seconds: 0),
      );
      expect(advanced.favorite, isFalse);
      expect(advanced.rating, 0);

      final withState = WatchState.fromDetail(
        MediaDetail.fromJson(loadFixture('media_detail_with_state')),
      );
      expect(withState.favorite, isTrue);
      expect(withState.rating, 8);
      expect(
        withState.pointer,
        const ResumePointer(file: FileIndex(0), seconds: 2),
      );
    });

    test(
      'index 0 at second 0 becomes NO pointer, not a pointer at the start',
      () {
        final plain = WatchState.fromDetail(
          MediaDetail.fromJson(loadFixture('media_detail_directplay')),
        );
        expect(plain.pointer, isNull);
      },
    );

    test('every state it builds is one setRating would accept', () {
      // The server rejects a write outside 0-10 but does NOT clamp on read:
      // verified live at v0.20.3 by editing meta.json to `rating: 99` —
      // `POST .../rating {"rating":99}` answered 400 while `GET .../media/<id>`
      // still served `"rating": 99`. Copied through unchecked, that builds a
      // WatchState whose own `setRating(state, rating: state.rating)` throws.
      // Out of range is read as 0, upstream's own value for "unrated".
      for (final entry in {
        0: 0,
        1: 1,
        5: 5,
        10: 10,
        -1: 0,
        11: 0,
        99: 0,
      }.entries) {
        final state = WatchState.fromDetail(
          MediaDetail(rating: entry.key),
        );
        expect(state.rating, entry.value, reason: 'server sent ${entry.key}');
        expect(
          () => setRating(state, rating: state.rating),
          returnsNormally,
          reason: 'server sent ${entry.key}',
        );
      }
    });

    test('the wire model still carries the raw value, tolerantly (§8)', () {
      // §8 tolerance belongs at the wire boundary; the normalisation belongs in
      // WatchState. Asserting both keeps them from drifting into each other.
      expect(
        MediaDetail.fromJson(const {'rating': 99}).rating,
        99,
      );
    });

    test('the derived view round-trips back to what the payload carried', () {
      final detail = MediaDetail.fromJson(
        loadFixture('media_detail_multifile_advanced'),
      );
      final view = deriveView(
        WatchState.fromDetail(detail),
        fileCount: detail.files.length,
      );
      expect(view.watched, detail.watched);
      expect(view.continueIndex, FileIndex(detail.continueIndex));
      expect(view.continueSeconds, detail.continueSeconds);
      expect(view.perFile, detail.files.map((f) => f.watched).toList());
    });
  });

  group('the two un-watch operations differ, deliberately', () {
    test('setWatched leaves the pointer where it is, both ways', () {
      final start = pointing(1, 45);
      final marked = setWatched(start, watched: true);
      expect(marked.watched, isTrue);
      expect(marked.pointer, start.pointer);

      final unmarked = setWatched(marked, watched: false);
      expect(unmarked.watched, isFalse);
      expect(unmarked.pointer, start.pointer);
    });

    test('clearWatched drops the flag AND the pointer', () {
      final out = clearWatched(pointing(1, 45, watched: true));
      expect(out.watched, isFalse);
      expect(out.pointer, isNull);
    });

    test('neither touches favorite or rating', () {
      const start = WatchState(watched: true, favorite: true, rating: 9);
      expect(setWatched(start, watched: false).rating, 9);
      expect(setWatched(start, watched: false).favorite, isTrue);
      expect(clearWatched(start).rating, 9);
      expect(clearWatched(start).favorite, isTrue);
    });
  });

  group('the remaining mutations', () {
    test('clearProgress drops the pointer and nothing else', () {
      final out = clearProgress(pointing(2, 30, watched: true));
      expect(out.pointer, isNull);
      expect(out.watched, isTrue);
    });

    test('setFavorite sets and clears', () {
      expect(setFavorite(const WatchState(), favorite: true).favorite, isTrue);
      expect(
        setFavorite(const WatchState(favorite: true), favorite: false).favorite,
        isFalse,
      );
      expect(
        setFavorite(pointing(1, 5), favorite: true).pointer,
        pointing(1, 5).pointer,
      );
    });

    test('setRating takes 1-10, and 0 clears', () {
      expect(setRating(const WatchState(), rating: 1).rating, 1);
      expect(setRating(const WatchState(), rating: 10).rating, 10);
      expect(setRating(const WatchState(rating: 8), rating: 0).rating, 0);
    });

    test('setRating rejects a value the server would answer with a 400', () {
      for (final bad in [-1, 11, 100]) {
        // The bounds carried in the error are asserted, not just its type: they
        // are what a developer reads when this fires, and an error naming the
        // wrong range sends them to look in the wrong place.
        expect(
          () => setRating(const WatchState(), rating: bad),
          throwsA(
            isA<RangeError>()
                .having((e) => e.invalidValue, 'invalidValue', bad)
                .having((e) => e.start, 'start', 0)
                .having((e) => e.end, 'end', 10)
                .having((e) => e.name, 'name', 'rating'),
          ),
          reason: 'rating $bad',
        );
      }
    });

    test('a rating survives clearing watched — Apply never touches it', () {
      const start = WatchState(watched: true, rating: 6);
      expect(clearWatched(start).rating, 6);
      expect(
        applyProgress(start, at(0, 50, 100), fileCount: 1).rating,
        6,
      );
    });
  });

  test('watchedThreshold is the constant upstream calls WatchedThreshold', () {
    expect(watchedThreshold, 0.90);
  });
}
