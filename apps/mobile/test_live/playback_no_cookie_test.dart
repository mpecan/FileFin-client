@Timeout(Duration(seconds: 180))
library;

import 'dart:async';
import 'dart:io';

import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/playback/media_kit_playback_host.dart';
import 'package:filefin_mobile/src/playback/mpv_player.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import '../test/support/libmpv.dart';
import 'support/live.dart';

/// The negative control for `playback_live_test.dart` **and** for
/// `hls_live_test.dart`, in its own process.
///
/// R1's discipline: a spike whose command cannot fail proves nothing. If the
/// same open succeeds without the session cookie, the positive test proved that
/// mpv can read a URL and nothing about authentication.
///
/// **Both routes, because both positives claimed the cookie and only one had a
/// control.** `hls_live_test.dart`'s duration assertion said it was "the
/// assertion that says the cookie survived onto the segments"; it is not —
/// removing the header kills that file forty seconds earlier, inside its
/// measurement, and every one of its five tests reports the same bare
/// `TimeoutException` (M5.R/T-F5). The falsifiable form is here: an open with
/// no header at all, bounded, where the *timeout is the pass*.
///
/// **It is a separate FILE because the control is otherwise vacuous, and that
/// was measured rather than reasoned.** `Media`'s constructor is
/// `httpHeaders ?? cache[uri]?.httpHeaders` over a **global static cache keyed
/// by URI** (`media_native.dart`), so a second `Media` for a URL any earlier
/// `Media` in the same process opened inherits that one's headers. At M4.0/E3
/// the cookie-less open "succeeded" in-process and failed correctly only when
/// re-run fresh. `flutter test` gives each file its own `flutter_tester`
/// process, so this file's cache starts empty.
///
/// The URI is distinguished as well, with a query parameter the handler cannot
/// see (`playback.go` contains no `Query().Get`). Two independent guards, both
/// cheap, because the failure mode of getting this wrong is a green suite that
/// checks nothing.
void main() {
  late _Refusal direct;
  late _Refusal hls;

  setUpAll(() async {
    HttpOverrides.global = null;
    ensureLibmpv();
    useHeadlessPlayer();

    final api = await liveApi();
    final categories = await api.categories();
    final films = categories.firstWhere((c) => c.leaf == 'Films');
    final shows = categories.firstWhere((c) => c.leaf == 'Shows');
    final film = (await api.categoryMedia(films.id)).single;
    final show = (await api.categoryMedia(shows.id)).single;

    final raw = Player();
    final host = MediaKitPlaybackHost(RealMpvPlayer.over(raw));
    addTearDown(host.dispose);

    final errors = <String>[];
    final sub = host.errors.listen(errors.add);
    addTearDown(sub.cancel);

    /// One cookie-less open, measured. Sequential on one engine rather than
    /// two `Player`s: a second mpv context in one process is what
    /// `hls_live_test.dart`'s header explains the cost of.
    Future<_Refusal> refuse(MediaId id, String label) async {
      errors.clear();
      final durationSeen = raw.stream.duration.firstWhere(
        (d) => d > Duration.zero,
      );
      await host.open(
        PlaybackRequest(
          url: api
              .fileUrl(id, const FileIndex(0))
              .replace(queryParameters: {'control': label}),
          headers: const {},
          startAt: Duration.zero,
          verifyTls: false,
        ),
      );
      await host.play();
      // A duration that never arrives is the expected outcome, so the wait is
      // bounded and its timeout is the *pass* rather than the failure.
      final duration = await durationSeen
          .timeout(const Duration(seconds: 15))
          .then<Duration?>((d) => d)
          .onError<TimeoutException>((_, _) => null);
      return _Refusal(duration: duration, errors: [...errors]);
    }

    direct = await refuse(film.id, 'no-cookie');
    hls = await refuse(show.id, 'no-cookie-hls');
  });

  test(
    'without the cookie the server refuses and mpv never gets a duration',
    () {
      expect(
        direct.duration,
        isNull,
        reason:
            'the same open WITH the cookie reports 3 seconds in '
            'playback_live_test.dart — if this one also succeeds, that test is '
            'proving nothing about authentication',
      );
    },
  );

  test('and mpv says so on its error stream, which is all it can say', () {
    // libmpv surfaces no status code — a 401 and a missing file are the same
    // sentence — which is exactly why `PlayerController` answers an error by
    // asking `me()` instead of parsing this string.
    expect(direct.errors, isNotEmpty);
    expect(direct.errors.first, contains('/file/0'));
  });

  test('the TRANSCODING route needs it too: no cookie, no duration', () {
    // The same question on the route that 307s to HLS. The playlist and every
    // segment sit behind `s.auth` (`server.go:283`), and this is the assertion
    // `hls_live_test.dart` was wrongly credited with.
    expect(
      hls.duration,
      isNull,
      reason:
          'hls_live_test.dart reports 3.023 s for this same file WITH the '
          'cookie — if this one also succeeds, that file proves nothing '
          'about authentication either',
    );
  });

  test('and the transcoding route says so on the same error stream', () {
    expect(hls.errors, isNotEmpty);
    expect(hls.errors.first, contains('/file/0'));
  });
}

/// What one cookie-less open produced: no duration, and mpv's own complaint.
class _Refusal {
  const _Refusal({required this.duration, required this.errors});

  final Duration? duration;
  final List<String> errors;
}
