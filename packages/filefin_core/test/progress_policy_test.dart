import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

/// The interval upstream uses, and the one every row below is written against.
const _interval = 30;

SentReport _sent(int file, int seconds) =>
    SentReport(file: FileIndex(file), positionSeconds: seconds);

ProgressDecision _decide({
  int file = 0,
  double position = 10,
  double duration = 100,
  ProgressEvent event = ProgressEvent.checkpoint,
  SentReport? lastSent,
  int intervalSecs = _interval,
}) => decideReport(
  file: FileIndex(file),
  position: position,
  duration: duration,
  event: event,
  lastSent: lastSent,
  intervalSecs: intervalSecs,
);

/// Names a decision so a table row can spell out the expectation literally
/// rather than recomputing the rule it is checking.
String _describe(ProgressDecision d) => switch (d) {
  SendProgress(:final report) =>
    'send(${report.file.value}, ${report.position}, ${report.event.name})',
  SkipProgress(:final reason) => 'skip(${reason.name})',
};

void main() {
  group('rule 1 — nothing to report before a duration exists', () {
    // Upstream's own guard is `if (!duration || !isFinite(duration)) return`
    // (web/src/views/library/Player.svelte). It is also what protects
    // roundReportedSeconds from a value .toInt() would throw on.
    for (final (name, position, duration) in <(String, double, double)>[
      ('duration 0', 10, 0),
      ('duration negative', 10, -1),
      ('duration NaN', 10, double.nan),
      ('duration infinite', 10, double.infinity),
      ('position NaN', double.nan, 100),
      ('position infinite', double.infinity, 100),
      ('position negative infinity', double.negativeInfinity, 100),
    ]) {
      test('$name is notStarted, whatever the event', () {
        for (final event in ProgressEvent.values) {
          expect(
            _describe(
              _decide(position: position, duration: duration, event: event),
            ),
            'skip(notStarted)',
            reason: 'for $event',
          );
        }
      });
    }
  });

  group('rule 2 — a checkpoint', () {
    test('sends when nothing has been sent yet', () {
      expect(_describe(_decide(position: 1)), 'send(0, 1.0, checkpoint)');
    });

    test('sends when the file changed, however small the move', () {
      expect(
        _describe(_decide(file: 1, position: 3, lastSent: _sent(0, 3))),
        'send(1, 3.0, checkpoint)',
      );
    });

    test('skips below the interval on the same file', () {
      expect(
        _describe(_decide(position: 29, lastSent: _sent(0, 0))),
        'skip(withinInterval)',
      );
    });

    test('sends exactly at the interval — the boundary is >=', () {
      expect(
        _describe(_decide(position: 30, lastSent: _sent(0, 0))),
        'send(0, 30.0, checkpoint)',
      );
    });

    test('sends on a backwards move of at least the interval', () {
      // `.abs()`, so a rewind reports as soon as it is large enough. Without
      // it a user who scrubbed backwards would report nothing until they had
      // played past their old position again.
      expect(
        _describe(_decide(position: 20, lastSent: _sent(0, 50))),
        'send(0, 20.0, checkpoint)',
      );
    });

    test('skips a backwards move below the interval', () {
      expect(
        _describe(_decide(position: 40, lastSent: _sent(0, 50))),
        'skip(withinInterval)',
      );
    });

    test('compares in the SERVER rounding, not the raw double', () {
      // round(29.5) is 30, so this is at the interval and must send, while
      // 29.49 is not. Comparing raw doubles would put both on the same side.
      expect(
        _describe(_decide(position: 29.5, lastSent: _sent(0, 0))),
        'send(0, 29.5, checkpoint)',
      );
      expect(
        _describe(_decide(position: 29.49, lastSent: _sent(0, 0))),
        'skip(withinInterval)',
      );
    });

    test('honours a configured interval other than 30', () {
      expect(
        _describe(
          _decide(position: 12, lastSent: _sent(0, 0), intervalSecs: 5),
        ),
        'send(0, 12.0, checkpoint)',
      );
      expect(
        _describe(
          _decide(position: 12, lastSent: _sent(0, 0), intervalSecs: 13),
        ),
        'skip(withinInterval)',
      );
    });
  });

  group('rule 3 — a terminal event ignores the interval', () {
    for (final event in ProgressEvent.values.where((e) => e.isTerminal)) {
      test('$event sends one second after the last report', () {
        expect(
          _describe(_decide(position: 1, lastSent: _sent(0, 0), event: event)),
          'send(0, 1.0, ${event.name})',
        );
      });

      test('$event skips the same file at the same rounded second', () {
        expect(
          _describe(
            _decide(position: 50, lastSent: _sent(0, 50), event: event),
          ),
          'skip(unchanged)',
        );
      });

      test('$event sends the same second on a DIFFERENT file', () {
        expect(
          _describe(
            _decide(
              file: 1,
              position: 50,
              lastSent: _sent(0, 50),
              event: event,
            ),
          ),
          'send(1, 50.0, ${event.name})',
        );
      });
    }

    test('checkpoint is the only non-terminal event', () {
      expect(ProgressEvent.checkpoint.isTerminal, isFalse);
      expect(
        ProgressEvent.values.where((e) => e.isTerminal).map((e) => e.name),
        ['pause', 'seek', 'ended', 'stop'],
      );
    });
  });

  group("the wire vocabulary is upstream's own", () {
    test('four of the five names are strings upstream sends', () {
      // web/src/views/library/Player.svelte sends exactly these four; `seek`
      // is ours, and the server ignores `event` entirely (state.Apply never
      // reads it), so adding one cannot change what it stores.
      expect(
        ProgressEvent.values.map((e) => e.wire),
        ['checkpoint', 'pause', 'seek', 'ended', 'stop'],
      );
    });
  });

  group("progressNeedsRefetch — M1's single-file divergence", () {
    ProgressReport report(double position, double duration) => ProgressReport(
      file: const FileIndex(0),
      position: position,
      duration: duration,
    );

    test('a crossing on a single-file item needs a refetch', () {
      expect(progressNeedsRefetch(report(90, 100), fileCount: 1), isTrue);
    });

    test('exactly at the threshold counts — the comparison is >=', () {
      expect(progressNeedsRefetch(report(89.9, 100), fileCount: 1), isFalse);
      expect(progressNeedsRefetch(report(90, 100), fileCount: 1), isTrue);
    });

    test('and so does everything ABOVE it — the comparison is not ==', () {
      // The boundary needs both sides asserted or `>=` and `==` are the same
      // function on every input the suite offers. `==` also happens to be the
      // shape a real player spends most of its crossing in: mpv's position
      // ticks land wherever they land, and 90/100 exactly is the one value it
      // will almost never report. Measured as a surviving mutant at M4.
      expect(progressNeedsRefetch(report(95, 100), fileCount: 1), isTrue);
      expect(progressNeedsRefetch(report(100, 100), fileCount: 1), isTrue);
      // The `ended` trigger's own shape: `position: duration` on the 3-second
      // seeded film, which is what `PlayerController` sends at `completed`.
      expect(progressNeedsRefetch(report(3, 3), fileCount: 1), isTrue);
    });

    test('a crossing on a multi-file item does NOT', () {
      // The pointer advance is exactly predictable there: next file, 0s.
      expect(progressNeedsRefetch(report(95, 100), fileCount: 2), isFalse);
      expect(progressNeedsRefetch(report(95, 100), fileCount: 9), isFalse);
    });

    test('a non-crossing report never does', () {
      expect(progressNeedsRefetch(report(10, 100), fileCount: 1), isFalse);
    });

    test('a zero or negative duration never crosses', () {
      expect(progressNeedsRefetch(report(10, 0), fileCount: 1), isFalse);
      expect(progressNeedsRefetch(report(10, -5), fileCount: 1), isFalse);
    });
  });

  group("roundReportedSeconds is the server's rounding, made public", () {
    test("is Go's int(x+0.5), clamped at 0", () {
      expect(roundReportedSeconds(29.5), 30);
      expect(roundReportedSeconds(29.49), 29);
      expect(roundReportedSeconds(-0.5), 0);
      expect(roundReportedSeconds(-100), 0);
      expect(roundReportedSeconds(double.nan), 0);
      expect(roundReportedSeconds(double.infinity), 0);
    });
  });
}
