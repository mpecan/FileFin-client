import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:filefin_mobile/src/playback/player_controls.dart';
import 'package:filefin_mobile/src/playback/player_page.dart';
import 'package:filefin_mobile/src/playback/player_transport.dart';
import 'package:filefin_mobile/src/servers/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_playback_host.dart';
import '../support/fakes.dart';

const _id = MediaId('919ac9caad25');

MediaDetail _show({bool transcode = true, int files = 2}) => MediaDetail(
  id: _id,
  title: 'Transcode Show',
  files: [
    for (var i = 0; i < files; i++)
      FileInfo(index: FileIndex(i), size: 10, transcode: transcode),
  ],
);

/// F12 on the player screen: the 415, from the variant to the sentence.
///
/// A file of its own because `player_page_test.dart` is already 449 lines and
/// `file-size`'s warning count may fall or hold, never rise.
void main() {
  final url = Uri.parse('https://media.example/api/media/abc/file/0');

  late FakeLibraryApi api;
  late FakePlaybackHost host;

  setUp(() {
    api = FakeLibraryApi()
      ..playbackHeadersResult = const PlaybackSessionHeaders({
        'Cookie': 'filefin_session=sess-1',
      })
      ..meResult = const AuthResult(user: 'sam');
    host = FakePlaybackHost();
  });

  PlayerController controllerFor(MediaDetail detail) {
    final controller = PlayerController(
      api: api,
      host: host,
      network: FakeNetworkStatus(),
      detail: detail,
      server: SavedServer(
        id: const ServerId('home'),
        name: 'Home',
        baseUrl: Uri.parse('http://nas.local'),
      ),
      prefs: const PlaybackPrefs(),
      initialFile: const FileIndex(0),
      startAt: Duration.zero,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('describeApiFailure names transcoding (F12)', () {
    test('the one line over the video is pinned exactly', () {
      // The "after" half of M5.0/E-I's before/after pair. The "before" was
      // mpv's own sentence, recorded verbatim in STATE.md:
      // `Failed to open http://127.0.0.1:8299/api/media/919ac9caad25/file/0.`
      expect(
        describeApiFailure(TranscodingDisabled(url)).$1,
        'This file needs transcoding and the server has it turned off.',
      );
    });

    test('it does not send the user to the sign-in screen', () {
      expect(describeApiFailure(TranscodingDisabled(url)).$2, isFalse);
    });

    test('the raw variant never leaks into the banner', () {
      // The hole §1 of the M5 plan found: `describeApiFailure` had a `_`
      // default arm, so a new variant would have rendered
      // `Playback could not start: TranscodingDisabled: … turned off` while
      // three other switches loudly demanded an answer. The `_` is gone; this
      // is the assertion that says so.
      final line = describeApiFailure(TranscodingDisabled(url)).$1;

      expect(line, isNot(contains('TranscodingDisabled')));
      expect(line, isNot(contains('Playback could not start')));
      expect(line, isNot(contains(url.toString())));
    });

    test('everything without its own wording still gets the generic line', () {
      // Every member of the grouped arm, one input each. A `||` chain is one
      // coverage line PER PATTERN — patterns are tried in order and stop at
      // the first match — so a chain exercised by two inputs leaves the other
      // ten uncovered, which `MAX_UNCOVERED=0` reported before this list
      // existed. Enumerating them is also what keeps the arm honest: if a
      // variant is ever moved out of the group and given its own wording, the
      // assertion below fails rather than the group silently shrinking.
      final generic = <FileFinApiException>[
        RequestTimedOut(RequestPhase.connect, url),
        RequestCancelled(url),
        ConnectionFailed(url),
        CacheUnavailable(url),
        RateLimited(Duration.zero, url),
        const MalformedIdentifier('', 'media id'),
        InvalidCredentials(url),
        NotAFileFinServerResponse(url, 'text/html'),
        MalformedResponse(url, 'expected an object'),
        ServerFailure(500, 'internal error', url),
        CertificateNotTrusted(
          url,
          fingerprint: 'AA:BB',
          subject: '/CN=nas',
          issuer: '/CN=nas',
          validTo: DateTime.utc(2027),
        ),
        CertificatePinMismatch(url, expected: 'AA:BB', actual: 'CC:DD'),
      ];

      for (final error in generic) {
        final line = describeApiFailure(error);
        expect(
          line.$1,
          startsWith('Playback could not start:'),
          reason: '${error.runtimeType} left the grouped arm',
        );
        expect(line.$2, isFalse, reason: '${error.runtimeType} wants sign-in');
      }
    });

    test('only the two named variants leave the generic arm', () {
      // The other side of the boundary. Four variants have their own wording,
      // and none of them may read as the generic sentence.
      for (final error in <FileFinApiException>[
        SessionExpired(url),
        TranscodingDisabled(url),
        BadRequest(url, 'bad file index'),
        NotFound(url),
      ]) {
        expect(
          describeApiFailure(error).$1,
          isNot(startsWith('Playback could not start:')),
          reason: '${error.runtimeType} fell into the grouped arm',
        );
      }
      expect(describeApiFailure(SessionExpired(url)).$2, isTrue);
    });
  });

  group('the pre-flight refuses before the engine is ever opened', () {
    test('a 415 becomes F12s sentence and host.open is NEVER called', () async {
      // The whole point of running it eagerly. `_recover` cannot help with a
      // 415 — it is permanent — so a lazy classification would put a black
      // surface in front of the user first and explain afterwards, which is
      // exactly M5.0/E-I's "before".
      api.requirePlayableResult = TranscodingDisabled(url);
      final controller = controllerFor(_show());

      await controller.start();

      expect(
        controller.failure,
        'This file needs transcoding and the server has it turned off.',
      );
      expect(controller.unplayable, isA<TranscodingDisabled>());
      expect(controller.needsSignIn, isFalse);
      // `anyElement(startsWith(...))`, and the shape is the finding rather
      // than a style choice: `open` is recorded as `'open($request)'`, so
      // `isNot(contains('open'))` is element EQUALITY against a string no
      // element can ever equal — it passed with `open` called, in a test named
      // for open never being called.
      expect(host.calls, isNot(anyElement(startsWith('open('))));
      expect(host.opened, isEmpty);
    });

    test('when it returns, the open happens exactly as before', () async {
      final controller = controllerFor(_show());

      await controller.start();

      expect(api.calls, contains('requirePlayable(919ac9caad25, 0)'));
      expect(host.opened, hasLength(1));
      expect(controller.failure, isNull);
      expect(controller.unplayable, isNull);
    });

    test('a direct-play file is NOT pre-flighted', () async {
      // The other side of the guard, and the reason it exists: §3.4 makes a
      // 415 on the file route reachable only for a file that needs
      // transcoding, so a pre-flight on a direct-play open would be a round
      // trip that can never answer anything. M4.R/T9's lesson — a boundary
      // tested on one side only had an off-by-one in its own fix.
      final controller = controllerFor(_show(transcode: false));

      await controller.start();

      expect(
        api.calls.where((c) => c.startsWith('requirePlayable')),
        isEmpty,
      );
      expect(host.opened, hasLength(1));
    });

    test(
      'next() pre-flights the file it is about to open, not the old one',
      () async {
        final controller = controllerFor(_show());
        await controller.start();

        await controller.next();

        expect(api.calls, contains('requirePlayable(919ac9caad25, 0)'));
        expect(api.calls, contains('requirePlayable(919ac9caad25, 1)'));
        expect(host.opened, hasLength(2));
      },
    );

    test('transcoding turned off mid-session stops at one retry', () async {
      // `_recover` spends its retry on the first engine error and re-opens;
      // the pre-flight refuses that re-open, and nothing loops. Without the
      // bound, a permanently-415 file would re-open forever behind a banner.
      //
      // **Asserted on the PRE-FLIGHT count and on the second sentence**, not
      // on `host.opened`. `opened` stays at 1 whether the bound exists or not,
      // because what stops the second open is the pre-flight refusing — so
      // deleting `_retrySpent = true` outright left all 15 tests in this file
      // green and the assertion whose reason read "the retry is spent, no
      // loop" was satisfied by something else entirely.
      final controller = controllerFor(_show());
      await controller.start();
      expect(host.opened, hasLength(1));
      int preflights() =>
          api.calls.where((c) => c.startsWith('requirePlayable')).length;
      expect(preflights(), 1);

      api.requirePlayableResult = TranscodingDisabled(url);
      host.emitError('Failed to open http://nas.local/…/file/0.');
      await pumpEventQueue();

      expect(host.opened, hasLength(1), reason: 'the re-open was refused');
      expect(preflights(), 2, reason: 'the one retry was spent here');
      expect(
        controller.failure,
        'This file needs transcoding and the server has it turned off.',
      );

      host.emitError('Failed to open http://nas.local/…/file/0.');
      await pumpEventQueue();

      expect(preflights(), 2, reason: 'the retry is spent: no second re-open');
      // And the banner now carries mpv's own words rather than F12's, which is
      // the observable difference between "the retry is spent" and "the retry
      // ran again and was refused again".
      expect(controller.failure, 'Failed to open http://nas.local/…/file/0.');
    });

    test('an ordinary failure leaves `unplayable` null', () async {
      // The absence half. `unplayable` gates a full-screen panel, and a panel
      // that appeared for a timeout would hide the video for a problem that
      // resolves itself.
      api.requirePlayableResult = CacheUnavailable(url);
      final controller = controllerFor(_show());

      await controller.start();

      expect(controller.failure, isNotNull);
      expect(controller.unplayable, isNull);
    });

    test('a successful re-open clears the refusal', () async {
      api.requirePlayableResult = TranscodingDisabled(url);
      final controller = controllerFor(_show());
      await controller.start();
      expect(controller.unplayable, isNotNull);

      api.requirePlayableResult = null;
      await controller.next();

      expect(controller.unplayable, isNull);
      expect(controller.failure, isNull);
    });
  });

  group('the panel F12 asks for, and where it must NOT appear', () {
    Future<void> pumpPlayer(
      WidgetTester tester, {
      required MediaDetail detail,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            api: api,
            hostFactory: () => host,
            nowPlayingFactory: fakeNowPlayingFactory(),
            network: FakeNetworkStatus(),
            detail: detail,
            server: SavedServer(
              id: const ServerId('home'),
              name: 'Home NAS',
              baseUrl: Uri.parse('http://nas.local'),
            ),
            prefs: const PlaybackPrefs(),
            initialFile: const FileIndex(0),
            startAt: Duration.zero,
            metrics: PlayerControlsMetrics.phone,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the refusal is a full-screen panel, worded exactly', (
      tester,
    ) async {
      api.requirePlayableResult = TranscodingDisabled(url);

      await pumpPlayer(tester, detail: _show());

      expect(
        find.text(
          'The file you asked for needs transcoding, and "Home NAS" has it '
          'turned off.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The server converts formats a player cannot read as they '
          'are. With that turned off there is nothing to play — nothing '
          'this app can change will help, so someone with admin access to '
          'the server has to turn it on.',
        ),
        findsOneWidget,
      );
      // Nothing behind it: the engine was never opened, so the surface would
      // be a black rectangle and the controls would drive nothing.
      expect(find.byKey(const ValueKey('fake-surface')), findsNothing);
      expect(find.byType(PlayerControls), findsNothing);
    });

    testWidgets('it is ABSENT on an ordinary failure', (tester) async {
      // M4.R/T5: dropping the D10 banner's guard left all 358 tests green
      // because nothing asserted absence. This is that assertion.
      api.requirePlayableResult = CacheUnavailable(url);

      await pumpPlayer(tester, detail: _show());

      expect(find.textContaining('needs transcoding'), findsNothing);
      // The ordinary failure banner is what shows instead, over a live player.
      expect(find.byKey(const ValueKey('fake-surface')), findsOneWidget);
      expect(find.byType(PlayerControls), findsOneWidget);
    });

    testWidgets('it is ABSENT on a successful open', (tester) async {
      await pumpPlayer(tester, detail: _show());

      expect(find.textContaining('needs transcoding'), findsNothing);
      expect(find.byKey(const ValueKey('fake-surface')), findsOneWidget);
    });
  });
}
