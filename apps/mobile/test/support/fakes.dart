import 'dart:typed_data';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';

/// A `LibraryApi` a widget test can make fail without opening a socket.
///
/// This is the whole reason `LibraryApi` is a port. Making a real request fail
/// inside `testWidgets` means a real server, `HttpOverrides.global = null`, and
/// `tester.runAsync` — because a real socket's callback never fires under
/// `FakeAsync` (measured at M3.0). Here it means assigning a field.
///
/// It `extend`s rather than `implement`s because `LibraryApi` is an
/// `abstract base class`: a method added there is a compile error here, which
/// an `implements` clause would let a stub silently satisfy.
///
/// **The answer ignores the arguments, so every test that cares which item was
/// asked for must read [calls].** M3's review found five shippable bugs that
/// passed the whole unit suite and the whole integration suite — a grid that
/// requested category 999, a detail page with a hard-coded media id, a tile
/// fetching a neighbour's poster, a dropped `?size=` hint, and a detail route
/// pushed with a fabricated item — because a fake that answers the same value
/// whatever it is handed cannot tell a right identifier from a wrong one.
/// [calls] records the arguments verbatim; asserting the exact string is what
/// closes that hole, and `expect(api.calls, contains('categoryMedia(1)'))`
/// costs one line more than `hasLength(1)`.
base class FakeLibraryApi extends LibraryApi {
  /// A fake for one server.
  FakeLibraryApi({this.server = const ServerId('fake')});

  @override
  final ServerId server;

  /// What `categories()` answers with, or throws.
  Object? categoriesResult;

  /// What `categoryMedia()` answers with, or throws.
  Object? categoryMediaResult;

  /// What `mediaDetail()` answers with, or throws.
  Object? mediaDetailResult;

  /// What `posterBytes()` answers with, or throws.
  Object? posterResult;

  /// What `probeServer()` answers with, or throws.
  Object? probeResult;

  /// What `login()` answers with, or throws.
  Object? loginResult;

  /// Every call made, in order, as `method(arg)`.
  final List<String> calls = [];

  /// The cancel tokens handed in, so a test can assert one was cancelled.
  final List<CancelToken?> tokens = [];

  /// Whether [close] has been called.
  bool closed = false;

  T _answer<T>(Object? result, String call, CancelToken? token) {
    calls.add(call);
    tokens.add(token);
    // A field that holds either the answer or the failure keeps the fake to
    // one line per case. `only_throw_errors` is right about production code
    // and wrong about a fake whose whole job is to reproduce whatever the real
    // API threw — including, deliberately, things that are neither.
    // ignore: only_throw_errors
    if (result is Object && result is! T) throw result;
    return result as T;
  }

  @override
  Future<ProbeResult> probeServer({CancelToken? cancelToken}) async =>
      _answer<ProbeResult>(probeResult, 'probeServer', cancelToken);

  @override
  Future<AuthResult> login(Credentials credentials) async =>
      _answer<AuthResult>(loginResult, 'login(${credentials.username})', null);

  @override
  Future<List<Category>> categories({CancelToken? cancelToken}) async =>
      _answer<List<Category>>(categoriesResult, 'categories', cancelToken);

  @override
  Future<List<MediaSummary>> categoryMedia(
    CategoryId id, {
    CancelToken? cancelToken,
  }) async => _answer<List<MediaSummary>>(
    categoryMediaResult,
    'categoryMedia(${id.value})',
    cancelToken,
  );

  @override
  Future<MediaDetail> mediaDetail(
    MediaId id, {
    CancelToken? cancelToken,
  }) async => _answer<MediaDetail>(
    mediaDetailResult,
    'mediaDetail(${id.value})',
    cancelToken,
  );

  @override
  Future<Uint8List?> posterBytes(
    MediaId id, {
    PosterSize? size,
    CancelToken? cancelToken,
  }) async => _answer<Uint8List?>(
    posterResult,
    // `size` is in the record because dropping the hint is invisible
    // otherwise: the server treats `?size=` as a hint it may ignore
    // (`media.go:351`), so a tile that asked for the full-size poster of every
    // item in a 5000-item grid still renders correctly and just moves far more
    // bytes than it needs to.
    'posterBytes(${id.value}, $size)',
    cancelToken,
  );

  @override
  void close() => closed = true;
}
