import 'package:dio/dio.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:test/test.dart';

import 'error_mapper_test.dart' show badResponse, requested;

/// The 415, from the wire to the words (F12).
///
/// A file of its own rather than three more cases in `error_mapper_test.dart`:
/// that file reached 432 lines when they were in it, and `file-size`'s warning
/// count may fall or hold and never rise. It shares `badResponse` with it, so
/// there is exactly one description of what a dio non-2xx looks like.
void main() {
  // The one route whose 415 SPEC §3.4 gives a meaning. `requested` — imported
  // above and pointing at `/api/me` — is deliberately NOT it: see the last two
  // tests in this file.
  final fileRoute = Uri.parse(
    'https://filefin.example/api/media/919ac9caad25/file/0',
  );

  test('415 is transcoding disabled — F12s variant, not ServerFailure', () {
    // Measured at M5.0/E-B against a real `transcodeEnabled:false` server:
    // `GET .../file/{n}` on a file that needs transcoding answers
    // `415 transcoding disabled` as `text/plain`, on every attempt, while the
    // detail payload keeps saying `transcode: true`. It is permanent, so it is
    // neither retryable nor `ServerFailure`'s "we have no opinion" landing
    // place.
    expect(
      mapDioException(
        badResponse(415, 'transcoding disabled'),
        requested: fileRoute,
      ),
      isA<TranscodingDisabled>(),
    );
  });

  test('415 keeps the URL it was asked for and nothing else', () {
    // The body is NOT carried, and under the HEAD pre-flight there is not one
    // to carry: measured at M5.0/E-K, a HEAD 415 arrives with an empty body.
    // The wording is the variant.
    final mapped =
        mapDioException(badResponse(415, ''), requested: fileRoute)
            as TranscodingDisabled;

    expect(mapped.requested, fileRoute);
  });

  test('the message is asserted verbatim, because prose is source', () {
    expect(
      TranscodingDisabled(requested).toString(),
      'TranscodingDisabled: https://filefin.example/api/me needs transcoding '
      'and the server has it turned off',
    );
  });

  test('a userInfo credential never reaches the message (§9, NF4)', () {
    final mapped = mapDioException(
      badResponse(415, 'transcoding disabled'),
      requested: Uri.parse(
        'https://sam:hunter2@filefin.example/api/media/abc/file/0',
      ),
    );

    expect(mapped.toString(), isNot(contains('hunter2')));
    expect(mapped.toString(), isNot(contains('sam')));
    expect(mapped.toString(), contains('filefin.example'));
  });

  test('a 415 is not a 400, a 404 or a 500', () {
    // The boundary on both sides: the arm is keyed on exactly 415, and the
    // statuses either side of it must keep their own variants.
    expect(
      mapDioException(badResponse(414, 'x'), requested: fileRoute),
      isA<ServerFailure>(),
    );
    expect(
      mapDioException(badResponse(416, 'x'), requested: fileRoute),
      isA<ServerFailure>(),
    );
    expect(
      mapDioException(badResponse(415, 'x'), requested: fileRoute),
      isNot(isA<ServerFailure>()),
    );
  });

  group('and it is scoped to the FILE route, because the sentence names a '
      'file', () {
    // `filefin` answers 415 on no other route, but a reverse proxy in front of
    // it answers one for a content type it dislikes on ANY route — and mapped
    // globally this variant put "This file needs transcoding" on the sign-in
    // and detail screens, about things that are not files.
    for (final route in <String>[
      '/api/login',
      '/api/me',
      '/api/media/919ac9caad25',
      // The three routes that EXTEND the file route's prefix. Anchoring is
      // what keeps them out: the HLS 415 says `not transcodable`, which is a
      // different sentence about a different question (SPEC §3.4).
      '/api/media/919ac9caad25/file/0/hls/index.m3u8',
      '/api/media/919ac9caad25/file/0/hls/seg0.ts',
      '/api/media/919ac9caad25/file/0/sub/0',
    ]) {
      test('a 415 from $route is a ServerFailure, not F12s variant', () {
        expect(
          mapDioException(
            badResponse(415, 'unsupported media type'),
            requested: Uri.parse('https://filefin.example$route'),
          ),
          isA<ServerFailure>(),
        );
      });
    }

    test('while a server under a PATH PREFIX still gets F12s variant', () {
      // Matched on the last segments on purpose: a reverse proxy that mounts
      // FileFin at /media is the same deployment that produces the 415s above.
      expect(
        mapDioException(
          badResponse(415, 'transcoding disabled'),
          requested: Uri.parse(
            'https://nas.example/media/api/media/919ac9caad25/file/0',
          ),
        ),
        isA<TranscodingDisabled>(),
      );
    });
  });

  test('a DioException with no response at all is still not a 415', () {
    expect(
      mapDioException(
        DioException(
          requestOptions: RequestOptions(path: '/api/me'),
          type: DioExceptionType.badResponse,
        ),
        requested: requested,
      ),
      isA<ConnectionFailed>(),
    );
  });
}
