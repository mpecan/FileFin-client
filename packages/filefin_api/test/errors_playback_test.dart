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
        requested: requested,
      ),
      isA<TranscodingDisabled>(),
    );
  });

  test('415 keeps the URL it was asked for and nothing else', () {
    // The body is NOT carried, and under the HEAD pre-flight there is not one
    // to carry: measured at M5.0/E-K, a HEAD 415 arrives with an empty body.
    // The wording is the variant.
    final mapped =
        mapDioException(badResponse(415, ''), requested: requested)
            as TranscodingDisabled;

    expect(mapped.requested, requested);
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
      requested: Uri.parse('https://sam:hunter2@filefin.example/api/x/file/0'),
    );

    expect(mapped.toString(), isNot(contains('hunter2')));
    expect(mapped.toString(), isNot(contains('sam')));
    expect(mapped.toString(), contains('filefin.example'));
  });

  test('a 415 is not a 400, a 404 or a 500', () {
    // The boundary on both sides: the arm is keyed on exactly 415, and the
    // statuses either side of it must keep their own variants.
    expect(
      mapDioException(badResponse(414, 'x'), requested: requested),
      isA<ServerFailure>(),
    );
    expect(
      mapDioException(badResponse(416, 'x'), requested: requested),
      isA<ServerFailure>(),
    );
    expect(
      mapDioException(badResponse(415, 'x'), requested: requested),
      isNot(isA<ServerFailure>()),
    );
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
