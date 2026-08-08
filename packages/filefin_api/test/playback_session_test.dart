import 'package:dio/dio.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:test/test.dart';

/// The two M4 types that carry no request of their own: the `400` variant, and
/// the headers value that hands libmpv a credential.
///
/// Split out of `playback_endpoints_test.dart` because that file crossed
/// `file-size`'s 400-line soft warning, and a gate warning may fall or hold and
/// never rise.
void main() {
  group(
    'a 400 is BadRequest, and it lands here rather than in ServerFailure',
    () {
      DioException badResponse(int status, String body) => DioException(
        requestOptions: RequestOptions(path: '/api/media/x/progress'),
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: RequestOptions(path: '/api/media/x/progress'),
          statusCode: status,
          data: body,
        ),
      );
      final requested = Uri.parse('https://nas.local/api/media/x/progress');

      test("a 400 is BadRequest, carrying the server's own sentence", () {
        // Captured live at v0.20.3: `POST .../progress` with a file index
        // outside `files[]` answers `400 bad file index`, and
        // `POST .../rating {"rating": 99}` answers `400 rating out of range`.
        for (final body in ['bad file index', 'rating out of range']) {
          final mapped = mapDioException(
            badResponse(400, body),
            requested: requested,
          );
          expect(
            mapped,
            isA<BadRequest>().having((e) => e.body, 'body', body),
          );
          expect(mapped.toString(), contains(body));
        }
      });

      test('a 400 is NOT a ServerFailure — retrying one always fails', () {
        expect(
          mapDioException(
            badResponse(400, 'bad file index'),
            requested: requested,
          ),
          isNot(isA<ServerFailure>()),
        );
        expect(
          mapDioException(badResponse(418, 'teapot'), requested: requested),
          isA<ServerFailure>(),
        );
      });
    },
  );

  group('PlaybackSessionHeaders is a value, and an unmodifiable one', () {
    test('equal headers compare and hash equal, whatever the key order', () {
      const a = PlaybackSessionHeaders({'Cookie': 'x', 'X-Trace': 'on'});
      const b = PlaybackSessionHeaders({'X-Trace': 'on', 'Cookie': 'x'});
      const c = PlaybackSessionHeaders({'Cookie': 'y'});
      const d = PlaybackSessionHeaders({'Cookie': 'x', 'X-Trace': 'off'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      expect(a, isNot(d));
      expect(a, isNot(const PlaybackSessionHeaders({})));
    });

    test("the map cannot be added to behind this package's back", () {
      const headers = PlaybackSessionHeaders({'Cookie': 'x'});
      expect(
        () => headers.headers['Authorization'] = 'Basic abc',
        throwsUnsupportedError,
      );
    });
  });
}
