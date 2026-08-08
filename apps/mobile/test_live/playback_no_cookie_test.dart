@Timeout(Duration(seconds: 120))
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

/// `playback_live_test.dart`'s negative control, **in its own process**.
///
/// R1's discipline: a spike whose command cannot fail proves nothing. If the
/// same open succeeds without the session cookie, the positive test proved that
/// mpv can read a URL and nothing about authentication.
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
  late List<String> errors;
  late Duration? duration;

  setUpAll(() async {
    HttpOverrides.global = null;
    ensureLibmpv();
    useHeadlessPlayer();

    final api = await liveApi();
    final categories = await api.categories();
    final films = categories.firstWhere((c) => c.leaf == 'Films');
    final film = (await api.categoryMedia(films.id)).single;

    final raw = Player();
    final host = MediaKitPlaybackHost(RealMpvPlayer.over(raw));
    addTearDown(host.dispose);

    errors = [];
    final sub = host.errors.listen(errors.add);
    addTearDown(sub.cancel);

    final durationSeen = raw.stream.duration.firstWhere(
      (d) => d > Duration.zero,
    );

    await host.open(
      PlaybackRequest(
        url: api
            .fileUrl(film.id, const FileIndex(0))
            .replace(queryParameters: {'control': 'no-cookie'}),
        headers: const {},
        startAt: Duration.zero,
        verifyTls: false,
      ),
    );
    await host.play();

    // A duration that never arrives is the expected outcome, so the wait is
    // bounded and its timeout is the *pass* rather than the failure.
    duration = await durationSeen
        .timeout(const Duration(seconds: 15))
        .then<Duration?>((d) => d)
        .onError<TimeoutException>((_, _) => null);
  });

  test(
    'without the cookie the server refuses and mpv never gets a duration',
    () {
      expect(
        duration,
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
    expect(errors, isNotEmpty);
    expect(errors.first, contains('/file/0'));
  });
}
