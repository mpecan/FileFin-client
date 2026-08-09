/// `WatchActions` — F10's writes, with no widget anywhere.
///
/// Plain `test()` bodies, because the class imports `foundation` and not
/// `material`: there is no binding to bring up and nothing to pump, which is
/// the same reason `AsyncController` is testable this way.
library;

import 'dart:async';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/watch_actions.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _id = MediaId('e4285edb34d5');

/// A two-file item, watched, with the pointer 45 seconds into the first file.
///
/// The shape the milestone turns on: un-watching it must put *Continue 0:45*
/// back, and clearing it must not.
const _watchedAt45 = MediaDetail(
  id: _id,
  title: 'Transcode Show',
  files: [
    FileInfo(),
    FileInfo(index: FileIndex(1)),
  ],
  watched: true,
  continueSeconds: 45,
);

void main() {
  late FakeLibraryApi api;
  late List<MediaDetail> published;
  late WatchActions actions;
  late bool disposed;

  setUp(() {
    api = FakeLibraryApi();
    published = [];
    disposed = false;
    actions = WatchActions(api: api, publish: published.add);
    // Guarded, because two cases below dispose deliberately and
    // `ChangeNotifier` asserts on a second dispose.
    addTearDown(() {
      if (!disposed) actions.dispose();
    });
  });

  group('the four writes reach the four methods', () {
    test('favourite toggles from what the payload says', () async {
      await actions.favourite(_watchedAt45, favorite: true);
      await actions.favourite(
        _watchedAt45.copyWith(favorite: true),
        favorite: false,
      );

      expect(api.calls, [
        'setFavorite(e4285edb34d5, true)',
        'setFavorite(e4285edb34d5, false)',
      ]);
      expect(published.map((d) => d.favorite).toList(), [true, false]);
    });

    test('rate sends the number, and 0 is how a rating is cleared', () async {
      await actions.rate(_watchedAt45, rating: 7);
      await actions.rate(_watchedAt45.copyWith(rating: 7), rating: 0);

      expect(api.calls, [
        'setRating(e4285edb34d5, 7)',
        'setRating(e4285edb34d5, 0)',
      ]);
      expect(published.map((d) => d.rating).toList(), [7, 0]);
    });

    test('markWatched POSTs and KEEPS the resume position', () async {
      // The centrepiece, at this layer. `setWatched(id, false)` is a different
      // call from `clearWatched(id)`, and the published payload is what the
      // Continue button is built from.
      await actions.markWatched(_watchedAt45, watched: false);

      expect(api.calls, ['setWatched(e4285edb34d5, false)']);
      expect(published.single.watched, isFalse);
      expect(published.single.continueSeconds, 45);
      expect(offerResume(published.single), isA<ResumeAvailable>());
    });

    test('clearWatchState DELETEs and DROPS the resume position', () async {
      await actions.clearWatchState(_watchedAt45);

      expect(api.calls, ['clearWatched(e4285edb34d5)']);
      expect(published.single.watched, isFalse);
      expect(published.single.continueSeconds, 0);
      expect(offerResume(published.single), isA<NoResume>());
    });

    test('the two are distinguishable in the record, by construction', () {
      // If this ever passes with one entry, the fake stopped being able to
      // tell them apart and every assertion above became decorative.
      expect(
        'setWatched(e4285edb34d5, false)',
        isNot('clearWatched(e4285edb34d5)'),
      );
    });
  });

  group('optimistic, and honest about it', () {
    test('the payload is published BEFORE the write returns', () async {
      final gate = Completer<void>();
      api.writeGate = gate;

      final pending = actions.favourite(_watchedAt45, favorite: true);
      await pumpEventQueue();

      expect(published.single.favorite, isTrue, reason: 'published already');
      expect(actions.busy, isTrue);
      gate.complete();
      await pending;
      expect(actions.busy, isFalse);
    });

    test('a failure reverts to exactly what was there, and says so', () async {
      api.writeFailure = CacheUnavailable(
        Uri.parse('http://server.invalid/api/media/x/favorite'),
      );

      await actions.favourite(_watchedAt45, favorite: true);

      expect(published.first.favorite, isTrue, reason: 'the optimistic value');
      expect(published.last, _watchedAt45, reason: 'reverted, field for field');
      expect(actions.notice, isNotNull);
      expect(actions.notice, contains('rebuilding'));
      expect(actions.wrote, isFalse);
    });

    test(
      'a success sets `wrote`, which is what reloads the home rows',
      () async {
        expect(actions.wrote, isFalse);
        await actions.rate(_watchedAt45, rating: 3);
        expect(actions.wrote, isTrue);
      },
    );

    test('a write that outlives the screen notifies nobody', () async {
      // `ChangeNotifier` asserts on `notifyListeners()` after disposal, and the
      // `finally` runs whenever the write answers — which is routinely after
      // the screen has gone. *Tap favourite, then Back before the response*
      // threw `A WatchActions was used after being disposed` in debug
      // (M6.R/P1.3). `AsyncController` has had this guard since M3, with a doc
      // comment explaining exactly why.
      final gate = Completer<void>();
      api.writeGate = gate;
      final pending = actions.favourite(_watchedAt45, favorite: true);
      await pumpEventQueue();

      actions.dispose();
      disposed = true;
      gate.complete();

      await expectLater(pending, completes);
    });

    test('a write still on the wire is a reason to reload the rows', () async {
      // What `MediaDetailPage` pops with. `wrote` alone is read at the instant
      // the screen closes, so a write that had not answered yet popped `false`
      // and Home never reloaded — even though the write landed.
      final gate = Completer<void>();
      api.writeGate = gate;
      final pending = actions.favourite(_watchedAt45, favorite: true);
      await pumpEventQueue();

      expect(actions.wrote, isFalse, reason: 'it has not answered yet');
      expect(actions.wroteOrWriting, isTrue);

      gate.complete();
      await pending;
      expect(actions.wroteOrWriting, isTrue);
    });

    test('nothing attempted is not a reason to reload — the other side', () {
      expect(actions.wroteOrWriting, isFalse);
    });

    test('a RangeError is a bug, not a refusal, so it is not caught', () async {
      // The client guards `0..10` and throws rather than sending. Nothing here
      // catches an Error: a rating outside the range can only come from a
      // control that offered it, and hiding that would hide the defect.
      api.writeFailure = RangeError.range(11, 0, 10, 'rating');

      await expectLater(
        actions.rate(_watchedAt45, rating: 5),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('exactly one write in flight, refused visibly', () {
    test(
      'a second write while one is running is refused, not queued',
      () async {
        final gate = Completer<void>();
        api.writeGate = gate;

        final first = actions.favourite(_watchedAt45, favorite: true);
        await pumpEventQueue();
        await actions.rate(_watchedAt45, rating: 9);

        expect(api.calls, ['setFavorite(e4285edb34d5, true)']);
        expect(
          actions.notice,
          'Still saving the last change. Try again in a '
          'moment.',
        );
        gate.complete();
        await first;
      },
    );

    test(
      'the refusal clears when the write it collided with finishes',
      () async {
        // It used to be cleared only by the NEXT ACCEPTED WRITE, so a red
        // sentence saying a save was under way sat on screen indefinitely after
        // that save had finished — on a screen the user may simply be reading
        // (M6.R/P1.5). The `finally` clears it now, because the reason for it is
        // gone the moment the write it named answers.
        final gate = Completer<void>();
        api.writeGate = gate;
        final first = actions.favourite(_watchedAt45, favorite: true);
        await pumpEventQueue();
        await actions.rate(_watchedAt45, rating: 9);
        expect(actions.notice, isNotNull, reason: 'refused while busy');

        gate.complete();
        await first;

        expect(actions.notice, isNull);
      },
    );

    test('a FAILURE is not cleared by the same finally', () async {
      // The other side of splitting the two sentences. A refusal is true only
      // while the write it collided with runs; a failure is true until the next
      // attempt, and one field could not hold both.
      api.writeFailure = CacheUnavailable(Uri.parse('http://nas/api'));

      await actions.favourite(_watchedAt45, favorite: true);

      expect(actions.notice, isNotNull);
      expect(actions.notice, contains('rebuilding'));
    });

    test('and the refusal does not leave the screen stuck', () async {
      final gate = Completer<void>();
      api.writeGate = gate;
      final first = actions.favourite(_watchedAt45, favorite: true);
      await pumpEventQueue();
      await actions.rate(_watchedAt45, rating: 9);
      gate.complete();
      await first;

      expect(actions.busy, isFalse);
      // A later write is accepted, and clears the refusal.
      api.writeGate = null;
      await actions.rate(_watchedAt45, rating: 9);
      expect(api.calls.last, 'setRating(e4285edb34d5, 9)');
      expect(actions.notice, isNull);
    });

    test('it notifies on every state change a control renders', () async {
      var notifications = 0;
      actions.addListener(() => notifications++);

      await actions.favourite(_watchedAt45, favorite: true);

      // Busy on, busy off. A control that never hears the second one stays
      // disabled forever.
      expect(notifications, 2);
    });
  });
}
