import 'package:dio/dio.dart';
import 'package:filefin_api/filefin_api.dart';
import 'package:test/test.dart';

/// A header that arrived **twice** must not escape the sealed hierarchy.
///
/// dio's `Headers.value` throws when a header has more than one value, and both
/// places this client reads a header used it: `Retry-After` on a 429 and
/// `Content-Type` on a 2xx. The first is the worse one — a caller doing
/// `on FileFinApiException` gets a raw `_Exception` at the exact moment login
/// is being rate limited — and no malice is needed to reach either, only a
/// proxy that folds or duplicates a header.
///
/// It lives in its own file because it is not reachable end to end: `dart:io`
/// collapses a repeated `Content-Type` before dio ever sees it, so the only
/// level that can hand the code a duplicate is dio's own `Headers`.
void main() {
  final requested = Uri.parse('https://filefin.example/api/me');
  final options = RequestOptions(path: '/api/me');

  DioException badResponse(int status, Map<String, List<String>> headers) =>
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: options,
          statusCode: status,
          data: 'too many requests',
          headers: Headers.fromMap({
            'content-type': ['text/plain'],
            ...headers,
          }),
        ),
      );

  Response<Object?> answer(List<String> contentTypes) => Response<Object?>(
    requestOptions: options,
    statusCode: 200,
    data: '{"user":"sam","admin":false}',
    headers: Headers.fromMap({'content-type': contentTypes}),
  );

  test('a duplicated Content-Type stays inside the sealed hierarchy', () {
    expect(
      jsonObject(
        answer(['application/json', 'application/json']),
        requested: requested,
      ),
      {'user': 'sam', 'admin': false},
    );
  });

  test('a response with no Content-Type at all is still not FileFin', () {
    expect(
      () => jsonObject(answer([]), requested: requested),
      throwsA(isA<NotAFileFinServerResponse>()),
    );
  });

  test('a duplicated Retry-After stays inside the sealed hierarchy', () {
    final mapped = mapDioException(
      badResponse(429, {
        'retry-after': ['900', '900'],
      }),
      requested: requested,
    );
    expect(mapped, isA<RateLimited>());
    expect((mapped as RateLimited).retryAfter, const Duration(seconds: 900));
  });
}
