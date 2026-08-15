import 'dart:async';
import 'dart:typed_data';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/library_api.dart';

/// The two small port fakes live next door and are re-exported here, so no
/// suite has to know which file a fake is in. They were split out at M7.3 for
/// `just file-size`, not for a reason anybody reading a test cares about.
export 'fake_ports.dart';

/// The URL a fake's `SessionExpired` names. Nothing renders it; the variant
/// requires one.
final Uri _nowhere = Uri.parse('http://fake.invalid/api/me');

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
/// passed both suites — a grid requesting category 999, a detail page with a
/// hard-coded media id, a tile fetching a neighbour's poster, a dropped
/// `?size=` hint, a detail route pushed with a fabricated item — because a
/// fake that answers the same value whatever it is handed cannot tell a right
/// identifier from a wrong one. [calls] records the arguments verbatim.
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

  /// What `signInWithToken()` answers with, or throws.
  Object? tokenSignInResult;

  /// Holds `restore()` open until a test completes it.
  ///
  /// F2's cold start builds a client BEFORE it knows whether the session is
  /// alive, so the launch being abandoned mid-restore is a real way to leak a
  /// socket — and proving the client is released needs a restore that is
  /// provably still running when the screen goes away.
  Completer<void>? restoreGate;

  /// What `restore()` throws, or `null` for a session that came back.
  ///
  /// **Defaults to `SessionExpired`**, because that is what a fresh
  /// `SecretStore` really produces and it is what every app test that is not
  /// about the cold start should see. A `null` default would have made every
  /// launch land signed in, which is the one outcome F2 has to earn.
  Object? restoreResult = SessionExpired(_nowhere);

  /// What `logout()` throws, or `null` for a server that answered.
  Object? logoutResult;

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

  /// What `home()` answers with, or throws.
  ///
  /// **The one field with a non-null default, and `LibraryShell` is why.** The
  /// shell opens on the Home tab, so from M6.7 every app-level test reaches
  /// `home()` on its first frame. A `null` here would make each of them throw
  /// a `TypeError` about `HomeRows` instead of failing on whatever the test
  /// was actually about — and three empty rows is what a fresh account really
  /// answers, so the default is the honest one rather than a convenience.
  Object? homeResult = const HomeRows();

  /// What `search()` answers with, or throws.
  Object? searchResult;

  /// What every watch-state write throws, or `null` for a `204`.
  Object? writeFailure;

  /// Holds every watch-state write open until a test completes it.
  ///
  /// A gate rather than a delay: F10 allows **one write in flight per screen**
  /// and refuses a second visibly, and proving that needs a write that is
  /// provably still running when the second tap arrives. A `Duration` under
  /// `FakeAsync` would need the test to guess how far to pump.
  Completer<void>? writeGate;

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

  /// Reproduces whatever the real API threw, if the test set anything. One
  /// helper rather than five copies of the same five lines, each of them a
  /// place for the `_answer<void>` trap [_write] names to creep back in.
  // `only_throw_errors` is right about production code and wrong about a fake
  // whose whole job is to reproduce a real failure, including things that are
  // neither an Exception nor an Error.
  // ignore: only_throw_errors
  void _rethrow(Object? failure) => failure == null ? null : throw failure;

  /// One `Future<void>` write: recorded, optionally held, optionally failed.
  ///
  /// **NOT `_answer<void>`, and this is the third place that trap has to be
  /// named.** With `T` bound to `void`, `result is! T` is false for every
  /// value, so the throw arm is unreachable and a fake set up to fail quietly
  /// succeeds — measured at M4, where four `ProgressReporter` failure tests
  /// passed against a fake that never threw. F10 reverts an optimistic update
  /// on failure, so a fake that cannot fail would leave that revert covered by
  /// nothing at all.
  Future<void> _write(String call, CancelToken? token) async {
    calls.add(call);
    tokens.add(token);
    final gate = writeGate;
    if (gate != null) await gate.future;
    _rethrow(writeFailure);
  }

  @override
  Future<ProbeResult> probeServer({CancelToken? cancelToken}) async =>
      _answer<ProbeResult>(probeResult, 'probeServer', cancelToken);

  @override
  Future<AuthResult> login(Credentials credentials) async =>
      _answer<AuthResult>(loginResult, 'login(${credentials.username})', null);

  @override
  Future<AuthResult> signInWithToken(ApiToken token) async =>
      _answer<AuthResult>(tokenSignInResult, 'signInWithToken', null);

  @override
  Future<void> restore() async {
    // Written out rather than routed through `_answer<void>`, for the trap
    // [_write] names below.
    calls.add('restore');
    final gate = restoreGate;
    if (gate != null) await gate.future;
    _rethrow(restoreResult);
  }

  @override
  Future<void> logout() async {
    // Same trap as [_write]: `_answer<void>` cannot throw, so the "logout that
    // fails still signs the user out" case would be vacuous through it.
    calls.add('logout');
    _rethrow(logoutResult);
  }

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
    // Same trap as [_write], and this is where it was measured: four
    // `ProgressReporter` failure tests passed against a fake that never threw.
    final delay = progressDelay;
    if (delay != null) await Future<void>.delayed(delay);
    _rethrow(progressResult);
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
    // guard M5.4 puts in front of this is per FILE. Written out rather than
    // routed through `_answer<void>`, for the trap [_write] names.
    calls.add('requirePlayable(${id.value}, ${file.value})');
    tokens.add(cancelToken);
    _rethrow(requirePlayableResult);
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
  Future<HomeRows> home({CancelToken? cancelToken}) async =>
      _answer<HomeRows>(homeResult, 'home', cancelToken);

  @override
  Future<List<MediaSummary>> search(
    String query, {
    SearchField field = SearchField.all,
    CancelToken? cancelToken,
  }) async => _answer<List<MediaSummary>>(
    searchResult,
    // The scope is in the record because sending the wrong one is invisible
    // otherwise: an unrecognised `field` degrades to `all` upstream
    // (`db/search.go:74`), so a screen that dropped the selector still returns
    // plausible results and quietly ignores what the user picked.
    'search($query, ${field.wire})',
    cancelToken,
  );

  @override
  Future<void> setFavorite(
    MediaId id, {
    required bool favorite,
    CancelToken? cancelToken,
  }) => _write('setFavorite(${id.value}, $favorite)', cancelToken);

  @override
  Future<void> setRating(
    MediaId id, {
    required int rating,
    CancelToken? cancelToken,
  }) => _write('setRating(${id.value}, $rating)', cancelToken);

  @override
  Future<void> setWatched(
    MediaId id, {
    required bool watched,
    CancelToken? cancelToken,
  }) => _write('setWatched(${id.value}, $watched)', cancelToken);

  @override
  Future<void> clearWatched(MediaId id, {CancelToken? cancelToken}) =>
      // Distinguishable from `setWatched(id, false)` by construction: these
      // two strings are the tripwire a UI that collapsed the two operations
      // into one boolean trips.
      _write('clearWatched(${id.value})', cancelToken);

  /// Releases the client, and **records it in [calls] like every other call**.
  ///
  /// The order is the assertion `HomeRoute._signOut` needs — `logout()` first,
  /// then the close, because closing releases the sockets the request travels
  /// on. Reverse those two statements and with the real client the
  /// `POST /api/logout` that ends the SERVER session never leaves the device.
  /// A fake recording only a boolean could not tell the two orders apart, and
  /// that reversal was green across the whole suite.
  ///
  /// **A fake that REFUSED every call after this would measure the harness**,
  /// not the app: every app-level suite hands out one fake per `apiFactory`
  /// call, so 36 `login`, 8 `probeServer` and 17 `home` calls land on a closed
  /// fake and none is a defect. STATE.md carries the gap and its fix.
  @override
  void close() {
    calls.add('close');
    closed = true;
  }
}
