import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/progress_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _id = MediaId('e4285edb34d5');
final Uri _url = Uri.parse('http://nas.local/api/media/${_id.value}/progress');

void main() {
  late FakeLibraryApi api;

  ProgressReporter reporterFor({
    int fileCount = 1,
    int intervalSecs = 30,
    WatchState initial = const WatchState(),
  }) => ProgressReporter(
    api: api,
    media: _id,
    intervalSecs: intervalSecs,
    fileCount: fileCount,
    initial: initial,
  );

  Future<ProgressDecision> tick(
    ProgressReporter reporter, {
    required int seconds,
    int file = 0,
    int durationSeconds = 100,
    ProgressEvent event = ProgressEvent.checkpoint,
  }) => reporter.report(
    file: FileIndex(file),
    position: Duration(seconds: seconds),
    duration: Duration(seconds: durationSeconds),
    event: event,
  );

  setUp(() {
    api = FakeLibraryApi();
  });

  group('the interval is media seconds, and there is no clock anywhere', () {
    test(
      'a first checkpoint posts; the next below the interval does not',
      () async {
        final reporter = reporterFor();

        await tick(reporter, seconds: 1);
        await tick(reporter, seconds: 10);
        await tick(reporter, seconds: 29);

        expect(api.reports.map((r) => r.position), [1.0]);
      },
    );

    test('the next checkpoint at the interval posts', () async {
      final reporter = reporterFor();

      await tick(reporter, seconds: 1);
      await tick(reporter, seconds: 31);

      expect(api.reports.map((r) => r.position), [1.0, 31.0]);
    });

    test('a pause posts immediately, however recent the last report', () async {
      final reporter = reporterFor();

      await tick(reporter, seconds: 1);
      await tick(reporter, seconds: 2, event: ProgressEvent.pause);

      expect(api.reports.map((r) => r.event), [
        ProgressEvent.checkpoint,
        ProgressEvent.pause,
      ]);
    });

    test('nothing is reported before a duration exists', () async {
      final reporter = reporterFor();

      final decision = await tick(reporter, seconds: 5, durationSeconds: 0);

      expect(decision, isA<SkipProgress>());
      expect(api.calls, isEmpty);
    });
  });

  group('the file is what every report is keyed on', () {
    test('the id and the file index reach the wire verbatim', () async {
      final reporter = reporterFor(fileCount: 3);

      await tick(reporter, file: 2, seconds: 7, event: ProgressEvent.seek);

      // Argument-aware: a reporter posting the right position against the
      // wrong file writes the resume pointer into the wrong episode, and the
      // server has no way to notice.
      expect(api.calls, ['postProgress(e4285edb34d5, 2, 7.0, 100.0, seek)']);
    });

    test('a file change posts even inside the interval', () async {
      final reporter = reporterFor(fileCount: 3);

      await tick(reporter, seconds: 10);
      await tick(reporter, file: 1, seconds: 11);

      expect(api.reports.map((r) => r.file.value), [0, 1]);
    });
  });

  group('local state is folded through the SAME engine the server runs', () {
    test('a successful report advances the optimistic pointer', () async {
      final reporter = reporterFor(fileCount: 2);

      await tick(reporter, seconds: 42);

      expect(reporter.state.pointer?.file.value, 0);
      expect(reporter.state.pointer?.seconds, 42);
    });

    test(
      'crossing 90% of a non-last file advances to the next at 0s',
      () async {
        final reporter = reporterFor(fileCount: 2);

        await tick(reporter, seconds: 95);

        expect(reporter.state.pointer?.file.value, 1);
        expect(reporter.state.pointer?.seconds, 0);
        expect(reporter.state.watched, isFalse);
        // Predictable, so no refetch is owed.
        expect(reporter.needsDetailRefetch, isFalse);
      },
    );

    test('crossing 90% of the LAST file sets watched', () async {
      final reporter = reporterFor(fileCount: 2);

      await tick(reporter, file: 1, seconds: 95);

      expect(reporter.state.watched, isTrue);
    });

    test(
      'a crossing on a single-file item latches needsDetailRefetch',
      () async {
        // M1's known limitation, discharged: `(0, 0)` is ambiguous on the
        // wire, so on a single-file item the prediction can outrun the server
        // and stay ahead until the detail is re-read.
        final reporter = reporterFor();

        await tick(reporter, seconds: 95);

        expect(reporter.needsDetailRefetch, isTrue);
      },
    );

    test('the latch is never cleared by a later ordinary report', () async {
      final reporter = reporterFor();

      await tick(reporter, seconds: 95);
      await tick(reporter, seconds: 10);

      expect(reporter.needsDetailRefetch, isTrue);
    });

    test('a failed report changes no local state at all', () async {
      final reporter = reporterFor();
      api.progressResult = ConnectionFailed(_url);

      await tick(reporter, seconds: 42);

      expect(reporter.state.pointer, isNull);
      expect(reporter.lastSent, isNull);
    });
  });

  group('failure arms — nothing here ever blocks playback', () {
    test(
      'a network failure keeps lastSent, so the next tick retries',
      () async {
        final reporter = reporterFor();
        api.progressResult = ConnectionFailed(_url);

        await tick(reporter, seconds: 10);
        api.progressResult = null;
        // Only 5 media seconds later: without the retained `lastSent` of null
        // this would be inside the interval and skipped, and the first report
        // would be lost for thirty seconds.
        await tick(reporter, seconds: 15);

        expect(api.reports.map((r) => r.position), [10.0, 15.0]);
        expect(reporter.stopped, isNull);
      },
    );

    test(
      'a cancellation is dropped silently and does not stop reporting',
      () async {
        final reporter = reporterFor();
        api.progressResult = RequestCancelled(_url);

        await tick(reporter, seconds: 10);

        expect(reporter.stopped, isNull);
        expect(reporter.lastSent, isNull);
      },
    );

    test('a SessionExpired stops reporting and says why', () async {
      final reporter = reporterFor();
      api.progressResult = SessionExpired(_url);

      await tick(reporter, seconds: 10);
      await tick(reporter, seconds: 90);

      expect(reporter.stopped, ReportStop.signedOut);
      // One attempt, not one per tick: a stopped reporter makes no requests.
      expect(api.reports, hasLength(1));
    });

    test('reporting resumes after a re-auth', () async {
      final reporter = reporterFor();
      api.progressResult = SessionExpired(_url);
      await tick(reporter, seconds: 10);

      api.progressResult = null;
      reporter.resume();
      await tick(reporter, seconds: 20);

      expect(reporter.stopped, isNull);
      expect(api.reports, hasLength(2));
    });

    test(
      'a BadRequest stops reporting — the file list changed under us',
      () async {
        final reporter = reporterFor();
        api.progressResult = BadRequest(_url, 'bad file index');

        await tick(reporter, seconds: 10);
        await tick(reporter, seconds: 90);

        // Retrying posts the same rejected body on every tick for as long as
        // playback lasts, which is why this variant is not retryable.
        expect(reporter.stopped, ReportStop.rejected);
        expect(api.reports, hasLength(1));
      },
    );
  });
}
