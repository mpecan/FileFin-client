import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_mobile/src/playback/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// F12 on the player screen: the 415, from the variant to the sentence.
///
/// A file of its own because `player_page_test.dart` is already 449 lines and
/// `file-size`'s warning count may fall or hold, never rise.
void main() {
  final url = Uri.parse('https://media.example/api/media/abc/file/0');

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
}
