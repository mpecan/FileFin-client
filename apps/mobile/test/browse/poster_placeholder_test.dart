import 'package:filefin_mobile/src/browse/poster_tile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Split out of `grid_test.dart` when that file crossed `just file-size`'s
/// 400-line soft warning, and gate warnings may fall or hold, never rise.
void main() {
  // The four cases of `Image`'s frameBuilder contract. Inline this condition
  // was unreachable from a widget test — a real decode is engine-side async
  // that a `testWidgets` body's fake clock does not drive — and `just
  // mutants` duly rewrote it two ways with the suite green. Both rewrites
  // are a tile that covers a poster it already has.
  test('nothing decoded yet, and not from the cache: still loading', () {
    expect(posterStillLoading(null, wasSync: false), isTrue);
  });

  test('a frame has arrived: not loading', () {
    expect(posterStillLoading(0, wasSync: false), isFalse);
  });

  test('already in the ImageCache on the first build: not loading', () {
    // `wasSync` is the cache hit. Treating it as loading would flash a
    // placeholder over a poster that was available immediately — which is
    // every tile scrolled back to.
    expect(posterStillLoading(null, wasSync: true), isFalse);
  });

  test('a later frame of a cached image: not loading', () {
    expect(posterStillLoading(1, wasSync: true), isFalse);
  });
}
