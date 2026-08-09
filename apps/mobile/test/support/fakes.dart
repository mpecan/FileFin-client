import 'dart:typed_data';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';
import 'package:filefin_mobile/src/playback/network_status.dart';
import 'package:filefin_mobile/src/playback/playback_host.dart';

import 'fake_playback_host.dart';

/// A `NetworkStatus` that answers whatever a test set, with no plugin.
final class FakeNetworkStatus extends NetworkStatus {
  /// Answers [answer] until a test changes it.
  FakeNetworkStatus([this.answer = NetworkType.wifi]);

  /// What the next sample returns.
  NetworkType answer;

  /// How many times it was sampled — F13 says exactly once, before playing.
  int samples = 0;

  @override
  Future<NetworkType> current() async {
    samples++;
    return answer;
  }
}

/// A playback host factory for a widget test: never libmpv, never a `Video`.
PlaybackHost Function() fakeHostFactory() => FakePlaybackHost.new;

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

  /// What `me()` answers with, or throws.
  Object? meResult;

  /// What `postProgress()` answers with, or throws. `null` is a 204.
  Object? progressResult;

  /// How long `postProgress()` takes before it answers.
  ///
  /// A server that stops answering is what the player's bounded final report
  /// exists for: without the bound, closing the route would hang on a dead
  /// server and trap the user on the player screen.
  Duration? progressDelay;

  /// What `subtitleText()` answers with, or throws.
  Object? subtitleResult;

  /// What `playbackHeaders()` answers with, or throws.
  Object? playbackHeadersResult;

  /// What `requirePlayable()` throws, or `null` for "the server will serve it".
  Object? requirePlayableResult;

  /// What `playbackTransport()` answers. Not a failure path — it does no I/O.
  PlaybackTransport transport = PlaybackTransport.plainHttp;

  /// The base every `fileUrl`/`subtitleUrl` is built from.
  Uri base = Uri.parse('http://stub.invalid');

  /// Every report handed to `postProgress`, in order.
  ///
  /// [calls] already records it as a string; this keeps the object, because a
  /// reporter test has to assert the *event* and the position the server was
  /// actually told, and re-parsing them out of a string would be a second
  /// encoding to get wrong.
  final List<ProgressReport> reports = [];

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
  Future<AuthResult> me({CancelToken? cancelToken}) async =>
      _answer<AuthResult>(meResult, 'me', cancelToken);

  @override
  Future<void> postProgress(
    MediaId id,
    ProgressReport report, {
    CancelToken? cancelToken,
  }) async {
    reports.add(report);
    // Every argument is in the record. A reporter that posted the right
    // position against the wrong FILE would write the resume pointer into the
    // wrong episode, and a fake that only counted calls could not tell.
    calls.add(
      'postProgress(${id.value}, ${report.file.value}, ${report.position}, '
      '${report.duration}, ${report.event.wire})',
    );
    tokens.add(cancelToken);
    // NOT `_answer<void>`, and the reason is a trap worth naming: with `T`
    // bound to `void`, `result is! T` is false for EVERY value, so the throw
    // arm is unreachable and a fake set up to fail quietly succeeds. Measured:
    // four `ProgressReporter` failure tests passed against a fake never threw.
    final delay = progressDelay;
    if (delay != null) await Future<void>.delayed(delay);
    final failure = progressResult;
    if (failure != null) {
      // The field holds whatever the real API threw, which is an Exception.
      // ignore: only_throw_errors
      throw failure;
    }
  }

  @override
  Future<String> subtitleText(
    MediaId id,
    FileIndex file,
    SubtitleIndex subtitle, {
    CancelToken? cancelToken,
  }) async => _answer<String>(
    subtitleResult,
    'subtitleText(${id.value}, ${file.value}, ${subtitle.value})',
    cancelToken,
  );

  @override
  Future<PlaybackSessionHeaders> playbackHeaders({
    CancelToken? cancelToken,
  }) async => _answer<PlaybackSessionHeaders>(
    playbackHeadersResult,
    'playbackHeaders',
    cancelToken,
  );

  @override
  Future<void> requirePlayable(
    MediaId id,
    FileIndex file, {
    CancelToken? cancelToken,
  }) async {
    // Both arguments in the record: a pre-flight that checked file 0 while the
    // player opened file 1 would pass a fake that only counted calls, and the
    // guard M5.4 puts in front of this is per FILE.
    calls.add('requirePlayable(${id.value}, ${file.value})');
    tokens.add(cancelToken);
    final failure = requirePlayableResult;
    // NOT `_answer<void>`, for the trap `postProgress` names above: with `T`
    // bound to `void`, `result is! T` is false for every value, so the throw
    // arm is unreachable and a fake set up to refuse quietly succeeds.
    if (failure != null) {
      // The field holds whatever the real API threw, which is an Exception.
      // ignore: only_throw_errors
      throw failure;
    }
  }

  @override
  Uri fileUrl(MediaId id, FileIndex file) {
    calls.add('fileUrl(${id.value}, ${file.value})');
    return base.replace(path: '/api/media/${id.value}/file/${file.value}');
  }

  @override
  Uri subtitleUrl(MediaId id, FileIndex file, SubtitleIndex subtitle) {
    calls.add('subtitleUrl(${id.value}, ${file.value}, ${subtitle.value})');
    return base.replace(
      path: '/api/media/${id.value}/file/${file.value}/sub/${subtitle.value}',
    );
  }

  @override
  PlaybackTransport playbackTransport() {
    calls.add('playbackTransport');
    return transport;
  }

  @override
  void close() => closed = true;
}
