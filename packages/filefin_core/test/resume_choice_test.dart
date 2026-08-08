import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

MediaDetail _detail({
  int files = 1,
  int continueIndex = 0,
  int continueSeconds = 0,
  bool watched = false,
}) => MediaDetail(
  id: const MediaId('abcdef012345'),
  files: [for (var i = 0; i < files; i++) FileInfo(index: FileIndex(i))],
  continueIndex: continueIndex,
  continueSeconds: continueSeconds,
  watched: watched,
);

String _describe(ResumeChoice choice) => switch (choice) {
  ResumeAvailable(:final file, :final seconds) =>
    'resume(${file.value}, ${seconds}s)',
  NoResume() => 'none',
};

void main() {
  group("offerResume — upstream's own rule, observed rather than invented", () {
    test('offers when the pointer is into a later file', () {
      expect(
        _describe(
          offerResume(_detail(files: 3, continueIndex: 1)),
        ),
        'resume(1, 0s)',
      );
    });

    test('offers when the pointer is seconds into the first file', () {
      expect(
        _describe(offerResume(_detail(continueSeconds: 42))),
        'resume(0, 42s)',
      );
    });

    test('does NOT offer at (0, 0) — the ambiguous case, never guessed', () {
      // `(0, 0)` is what the server reports for a fresh item AND for a pointer
      // whose ref no longer resolves. Upstream's own client treats it as no
      // resume (`hasResume` in web/src/lib/app.svelte.js:423), which is how M4
      // avoids ever seeking to a position it made up.
      expect(_describe(offerResume(_detail())), 'none');
    });

    test('does NOT offer a watched item, however far the pointer', () {
      expect(
        _describe(
          offerResume(
            _detail(
              files: 3,
              continueIndex: 2,
              continueSeconds: 5,
              watched: true,
            ),
          ),
        ),
        'none',
      );
    });

    test('a pointer past the end normalises to no resume', () {
      // The stale-ref case the 601 captured vectors exist for: the payload
      // says index 7 of a 2-file item, `deriveView` resolves that to nothing,
      // and this must not offer to seek into a file that is not there.
      expect(
        _describe(
          offerResume(_detail(files: 2, continueIndex: 7, continueSeconds: 45)),
        ),
        'none',
      );
    });

    test('a negative pointer index normalises to no resume too', () {
      expect(
        _describe(
          offerResume(
            _detail(files: 2, continueIndex: -1, continueSeconds: 45),
          ),
        ),
        'none',
      );
    });

    test('an item with no files at all offers nothing', () {
      expect(
        _describe(
          offerResume(_detail(files: 0, continueSeconds: 30)),
        ),
        'none',
      );
    });
  });

  group('startSecondsFor — resume only the file the pointer names', () {
    test('the continue file starts at the resume position', () {
      final d = _detail(files: 3, continueIndex: 1, continueSeconds: 42);
      expect(startSecondsFor(d, const FileIndex(1)), 42);
    });

    test('any other file starts at zero', () {
      // `playFile(idx)` upstream seeks only when `idx == continueIndex`
      // (web/src/lib/app.svelte.js:864). Picking episode 1 after leaving off in
      // episode 2 starts episode 1 at the beginning, which is what a user who
      // tapped that row asked for.
      final d = _detail(files: 3, continueIndex: 1, continueSeconds: 42);
      expect(startSecondsFor(d, const FileIndex(0)), 0);
      expect(startSecondsFor(d, const FileIndex(2)), 0);
    });

    test('a watched item starts every file at zero', () {
      final d = _detail(
        files: 3,
        continueIndex: 1,
        continueSeconds: 42,
        watched: true,
      );
      expect(startSecondsFor(d, const FileIndex(1)), 0);
    });

    test(
      'the ambiguous (0, 0) starts at zero, which is also what it means',
      () {
        expect(startSecondsFor(_detail(), const FileIndex(0)), 0);
      },
    );

    test('a stale pointer starts at zero rather than at its own seconds', () {
      final d = _detail(files: 2, continueIndex: 7, continueSeconds: 45);
      expect(startSecondsFor(d, const FileIndex(0)), 0);
      expect(startSecondsFor(d, const FileIndex(1)), 0);
    });
  });
}
