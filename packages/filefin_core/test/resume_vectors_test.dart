import 'dart:convert';

import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

/// Replays `test/fixtures/resume_vectors.json` — 601 input→output pairs
/// captured from the real `state.Apply` / `state.View` at v0.20.3 — against
/// this package's engine.
///
/// This is the strongest guarantee in M1, because the expectations were not
/// written by anyone. A hand-written expectation can only encode what we
/// already believe; these encode what the server does.
///
/// The vectors address the pointer by **ref string** and this engine addresses
/// it by index, so each vector is translated on the way in and on the way out.
/// The translation is where the interesting case lives — see [_pointerOf].
void main() {
  final fixture =
      jsonDecode(fixtureText('resume_vectors.json')) as Map<String, Object?>;
  final vectors = (fixture['vectors']! as List<Object?>)
      .cast<Map<String, Object?>>();

  test('the fixture is the grid that was captured, not a truncated one', () {
    expect(fixture['source'], contains('engine.go @ v0.20.3'));
    expect(fixture['watchedThreshold'], watchedThreshold);
    expect(vectors, hasLength(601));
  });

  test('the grid still contains what separates right from plausible', () {
    // A vector whose output pointer carries real seconds while its view reports
    // 0. `continueSeconds = pointer?.seconds ?? 0` passes every other vector in
    // the file and fails these. If this count ever reaches zero the oracle has
    // stopped asking the only question it was re-captured to ask.
    final trap = vectors.where((v) {
      final out = v['out']! as Map<String, Object?>;
      final pointer = out['pointer'] as Map<String, Object?>?;
      final view = out['view']! as Map<String, Object?>;
      return pointer != null &&
          pointer['seconds'] != 0 &&
          view['continueSeconds'] == 0;
    });
    expect(trap, hasLength(18));
  });

  for (final vector in vectors) {
    final name = vector['name']! as String;
    final input = vector['in']! as Map<String, Object?>;
    final output = vector['out']! as Map<String, Object?>;
    final refs = (input['refs']! as List<Object?>).cast<String>();

    test('vector $name', () {
      final state = WatchState(
        pointer: _pointerOf(input['pointer'], refs),
        watched: input['watched']! as bool,
      );
      final report = ProgressReport(
        file: FileIndex(input['file']! as int),
        position: (input['position']! as num).toDouble(),
        duration: (input['duration']! as num).toDouble(),
      );

      final applied = applyProgress(state, report, fileCount: refs.length);
      expect(applied.watched, output['watched'], reason: 'watched');
      expect(
        applied.pointer,
        _pointerOf(output['pointer'], refs),
        reason: 'pointer',
      );

      final expectedView = output['view']! as Map<String, Object?>;
      final view = deriveView(applied, fileCount: refs.length);
      expect(view.watched, expectedView['watched'], reason: 'view.watched');
      expect(
        view.continueIndex,
        FileIndex(expectedView['continueIndex']! as int),
        reason: 'view.continueIndex',
      );
      expect(
        view.continueSeconds,
        expectedView['continueSeconds'],
        reason: 'view.continueSeconds',
      );
      expect(
        view.perFile,
        (expectedView['perFile']! as List<Object?>).cast<bool>(),
        reason: 'view.perFile',
      );
    });
  }
}

/// Translates a captured `{"file": <ref>, "seconds": n}` into an index-space
/// pointer.
///
/// A ref that **is** in [refs] maps to its position, exactly as upstream's
/// `indexOf` finds it.
///
/// A ref that is not maps to `refs.length` — deliberately out of range, and
/// deliberately not `null`. Upstream keeps a non-nil `Progress` in that case
/// and resolves it to -1 at every read; collapsing it to `null` here would
/// still
/// reproduce every *observable* value, but it would also erase the distinction
/// the 18 trap vectors exist to test, and this engine would pass them for the
/// wrong reason. An index past the end of the list is what the same situation
/// looks like on the client: a file list that shrank between sessions.
ResumePointer? _pointerOf(Object? captured, List<String> refs) {
  if (captured == null) return null;
  final pointer = captured as Map<String, Object?>;
  final index = refs.indexOf(pointer['file']! as String);
  return ResumePointer(
    file: FileIndex(index >= 0 ? index : refs.length),
    seconds: pointer['seconds']! as int,
  );
}
