@Timeout(Duration(seconds: 60))
library;

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/harness.dart';

/// F10's four writes against the real binary, and M6's exit criterion.
///
/// **The POST/DELETE watched distinction is what this file exists for.** Until
/// M6.0 nothing in this repository had ever exercised it: `POST
/// .../watched {"watched": false}` and `DELETE .../watched` were documented as
/// different operations and never observed to be. They are, and the difference
/// is a user's resume position — so it is pinned here against a live server
/// rather than against our own belief about one.
///
/// **Every step is differential, as `playback_test.dart`'s are.**
/// `applyWatchState` is what the detail screen publishes *before* the round
/// trip finishes (F10's optimistic update), so every assertion below compares
/// three things: what the pure function predicted, what the server's own detail
/// payload says afterwards, and — where a home row is involved — which bucket
/// the item landed in. A prediction that is optimistic and wrong is worse than
/// no prediction, and only a live server can say which it is.
///
/// **Each test creates the state it asserts on, and that is forced rather than
/// preferred (M6.0/E-2).** A `FixtureRun` copy starts with the `user_state`
/// mirror *contradicting* `meta.json` in both directions — the film's
/// `meta.json` says watched while the copied mirror says the show is — so
/// `/api/home`, search and the category listings each report the OPPOSITE of
/// `/api/media/{id}` until something writes. One write repairs one row, so a
/// suite that writes before it reads is reproducible on any machine; a suite
/// that trusted the seeded mirror would be asserting whatever the last
/// `fixtures-capture` happened to leave behind.
void main() {
  late FileFinClient client;
  late MediaId show;

  setUp(() async {
    final server = await startServer();
    client = FileFinClient.forServer(
      server: seededServer,
      baseUrl: server.baseUrl,
      secrets: InMemorySecretStore(),
    );
    addTearDown(client.close);
    await client.login(seededCredentials);
    final categories = await client.categories();
    show = (await client.categoryMedia(
      categories.firstWhere((c) => c.leaf == 'Shows').id,
    )).single.id;
  });

  /// The item as the server holds it, and as `WatchState.fromDetail` reads it.
  Future<MediaDetail> detail(MediaId id) => client.mediaDetail(id);

  /// Which home buckets [id] is in, by the server's own reckoning.
  Future<Set<String>> buckets(MediaId id) async {
    final rows = await client.home();
    return {
      if (rows.continueRow.any((m) => m.id == id)) 'continue',
      if (rows.favorites.any((m) => m.id == id)) 'favorites',
      if (rows.completed.any((m) => m.id == id)) 'completed',
    };
  }

  /// Runs [write], then asserts the server ended up where [predict] said.
  ///
  /// The prediction is made from the payload the server *had*, so both sides
  /// see the same input and any disagreement belongs to the round trip.
  Future<MediaDetail> writeAndCompare(
    MediaId id,
    WatchState Function(WatchState before) predict,
    Future<void> Function() write,
  ) async {
    final before = await detail(id);
    final predicted = applyWatchState(
      before,
      predict(WatchState.fromDetail(before)),
    );

    await write();

    final after = await detail(id);
    expect(after.watched, predicted.watched, reason: 'watched');
    expect(after.favorite, predicted.favorite, reason: 'favorite');
    expect(after.rating, predicted.rating, reason: 'rating');
    expect(
      after.continueIndex,
      predicted.continueIndex,
      reason: 'continueIndex',
    );
    expect(
      after.continueSeconds,
      predicted.continueSeconds,
      reason: 'continueSeconds — the optimistic update would have lied',
    );
    return after;
  }

  test('the six steps of the POST/DELETE distinction, in order', () async {
    // The exit criterion, and the one sequence nothing in this repository had
    // ever run before M6. Written as one test because the steps are a state
    // machine: step 4 only means anything given steps 1-3.

    // 1. A clean slate. DELETE is the only reset that also nils the pointer.
    await client.clearWatched(show);
    expect((await detail(show)).continueSeconds, 0);
    expect(await buckets(show), isEmpty);

    // 2. Forty-five seconds in.
    await client.postProgress(
      show,
      const ProgressReport(file: FileIndex(0), position: 45, duration: 100),
    );
    expect((await detail(show)).continueSeconds, 45);
    expect(await buckets(show), contains('continue'));

    // 3. Watched. The pointer stays where it was.
    var after = await writeAndCompare(
      show,
      (before) => setWatched(before, watched: true),
      () => client.setWatched(show, watched: true),
    );
    expect(after.watched, isTrue);
    expect(await buckets(show), contains('completed'));

    // 4. THE STEP. `POST {"watched": false}` keeps the position, so the item
    // comes back to Continue watching still 45 seconds in. Pointing the client
    // at `clearWatched` here turns this line red, which is the proof M6's plan
    // calls the single most valuable mutation to try.
    after = await writeAndCompare(
      show,
      (before) => setWatched(before, watched: false),
      () => client.setWatched(show, watched: false),
    );
    expect(after.watched, isFalse);
    expect(after.continueSeconds, 45, reason: 'the POST arm KEEPS the pointer');
    expect(await buckets(show), contains('continue'));

    // 5. Watched again, so the DELETE has something to clear.
    await client.setWatched(show, watched: true);
    expect(await buckets(show), contains('completed'));

    // 6. `DELETE` forgets the position too, so it leaves every list.
    after = await writeAndCompare(
      show,
      clearWatched,
      () => client.clearWatched(show),
    );
    expect(after.watched, isFalse);
    expect(after.continueSeconds, 0, reason: 'the DELETE arm NILS the pointer');
    expect(after.continueIndex, 0);
    expect(await buckets(show), isEmpty);
  });

  test('a favourite reaches the favourites row, and comes back out', () async {
    await writeAndCompare(
      show,
      (before) => setFavorite(before, favorite: true),
      () => client.setFavorite(show, favorite: true),
    );
    expect(await buckets(show), contains('favorites'));

    await writeAndCompare(
      show,
      (before) => setFavorite(before, favorite: false),
      () => client.setFavorite(show, favorite: false),
    );

    expect(await buckets(show), isNot(contains('favorites')));
  });

  test('a rating round-trips, and 0 is how it is cleared', () async {
    await writeAndCompare(
      show,
      (before) => setRating(before, rating: 7),
      () => client.setRating(show, rating: 7),
    );
    expect((await detail(show)).rating, 7);

    await writeAndCompare(
      show,
      (before) => setRating(before, rating: 0),
      () => client.setRating(show, rating: 0),
    );

    expect((await detail(show)).rating, 0);
  });

  test(
    'the range guard refuses before a socket opens, on both sides',
    () async {
      // 0 and 10 are legal and 11 is not (M6.0/E-6: the server answers `400
      // rating out of range`). The client refuses locally so the user is told
      // "that is not a rating" instead of "the item changed on the server".
      await client.setRating(show, rating: 10);
      expect((await detail(show)).rating, 10);

      expect(
        () => client.setRating(show, rating: 11),
        throwsA(isA<RangeError>()),
      );
      expect(
        () => client.setRating(show, rating: -1),
        throwsA(isA<RangeError>()),
      );

      expect((await detail(show)).rating, 10, reason: 'nothing was written');
    },
  );

  test('every write re-stamps `updated`, so the rows re-order (E-3)', () async {
    // Measured at M6.0 and pinned here: `UpdateStateGet` stamps
    // `us.Updated = time.Now().Unix()` whatever the fold did, and every bucket
    // is `ORDER BY us.updated DESC`. A rating re-orders the *continue* row.
    // This is why the home screen refetches rather than predicting.
    final categories = await client.categories();
    final film = (await client.categoryMedia(
      categories.firstWhere((c) => c.leaf == 'Films').id,
    )).single.id;

    for (final id in [film, show]) {
      await client.clearWatched(id);
      await client.postProgress(
        id,
        const ProgressReport(file: FileIndex(0), position: 5, duration: 100),
      );
    }
    // The show moved last, so it is first.
    expect((await client.home()).continueRow.first.id, show);

    // A RATING on the film — nothing to do with progress — moves it to front.
    await client.setRating(film, rating: 5);

    expect((await client.home()).continueRow.first.id, film);
  });

  test('the mirror and the truth: one write repairs one row (E-2)', () async {
    // The divergence M6.0 measured, exposed rather than reconciled. In a fresh
    // copy `meta.json` says the film is watched and the copied `user_state`
    // mirror says the show is, so a listing's `watched` flag is the OPPOSITE
    // of the detail's — on every machine, in every copy. `MediaSummary.watched`
    // comes from the mirror (`server/search.go:47-60`) and
    // `MediaDetail.watched` from `meta.json` via `state.View`.
    final categories = await client.categories();
    final films = categories.firstWhere((c) => c.leaf == 'Films').id;
    final film = (await client.categoryMedia(films)).single;

    // Before any write: the two disagree. This is the bug-shaped truth.
    final truth = await detail(film.id);
    expect(truth.watched, isTrue, reason: 'meta.json marks the film watched');
    expect(
      film.watched,
      isFalse,
      reason: 'the copied mirror has not been told',
    );

    // One write rewrites the row from `meta.json`, and they agree again.
    await client.setFavorite(film.id, favorite: true);

    final repaired = (await client.categoryMedia(films)).single;
    expect(repaired.watched, truth.watched);
  });
}
