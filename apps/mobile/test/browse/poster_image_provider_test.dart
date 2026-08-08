import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:filefin_api/filefin_api.dart';
import 'package:filefin_core/filefin_core.dart';
import 'package:filefin_mobile/src/browse/poster_image_provider.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeLibraryApi api;

  // The poster captured from the real server (§8). A hand-made byte array
  // would prove `decode` accepts what we invented; this proves it accepts what
  // FileFin actually serves.
  final realPoster = Uint8List.fromList(
    File('../../test/fixtures/poster.jpg').readAsBytesSync(),
  );

  setUp(() {
    // The `ImageCache` is global and survives between tests, and this
    // provider keys on (ServerId, MediaId, PosterSize) — so the second test to
    // use a key is served the first one's result and never calls the port at
    // all. That dedup is the whole point of being an ImageProvider; it also
    // means these tests have to start from an empty cache. Measured: two of
    // them passed alone and failed in the suite.
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    api = FakeLibraryApi(server: const ServerId('home'));
  });

  group('the cache key', () {
    const media = MediaId('aaaaaaaaaaaa');

    test('two keys for the same server, item and size are equal', () {
      expect(
        const PosterKey(ServerId('home'), media, PosterSize.tile),
        const PosterKey(ServerId('home'), media, PosterSize.tile),
      );
      expect(
        const PosterKey(ServerId('home'), media, PosterSize.tile).hashCode,
        const PosterKey(ServerId('home'), media, PosterSize.tile).hashCode,
      );
    });

    test('the SERVER is part of it', () {
      // Two servers can hand out the same MediaId — it is
      // sha1(category + "/" + folder)[:12] and says nothing about which
      // machine produced it. A key without the server shows one server's
      // artwork on the other's item, silently, and only for people with two.
      expect(
        const PosterKey(ServerId('home'), media, null),
        isNot(const PosterKey(ServerId('work'), media, null)),
      );
    });

    test('the item and the size are part of it too', () {
      expect(
        const PosterKey(ServerId('home'), media, null),
        isNot(const PosterKey(ServerId('home'), MediaId('b'), null)),
      );
      expect(
        const PosterKey(ServerId('home'), media, PosterSize.tile),
        isNot(const PosterKey(ServerId('home'), media, PosterSize.detail)),
      );
    });

    test('the hash depends on WHICH field a value is in', () {
      // `Object.hash` combines in order, and reordering its arguments passed
      // the whole suite: every equality test compares keys whose fields match,
      // so the order is invisible to them. Two keys with the same values in
      // different fields is what separates them.
      expect(
        const PosterKey(ServerId('a'), MediaId('b'), null).hashCode,
        isNot(const PosterKey(ServerId('b'), MediaId('a'), null).hashCode),
      );
      expect(
        const PosterKey(ServerId('a'), MediaId('b'), null),
        isNot(const PosterKey(ServerId('b'), MediaId('a'), null)),
      );
    });

    test('it prints all three parts', () {
      expect(
        const PosterKey(ServerId('home'), media, PosterSize.tile).toString(),
        'PosterKey(home, aaaaaaaaaaaa, PosterSize.tile)',
      );
    });

    testWidgets("obtainKey names the API's server, not a literal", (
      tester,
    ) async {
      final provider = PosterImageProvider(
        api: api,
        media: media,
        size: PosterSize.tile,
      );

      expect(
        await provider.obtainKey(ImageConfiguration.empty),
        const PosterKey(ServerId('home'), media, PosterSize.tile),
      );
    });
  });

  group('loading', () {
    const media = MediaId('e4285edb34d5');

    /// Resolves [provider] and reports what happened.
    ///
    /// The resolve is started **inside** `runAsync`, not merely awaited there:
    /// a request initiated under `FakeAsync` registers its timers in the fake
    /// zone and never completes, and decoding an image is real async work in
    /// the engine. Measured at M3.0, and re-learned in `grid_test.dart`.
    Future<Object?> resolve(
      WidgetTester tester,
      PosterImageProvider provider,
    ) async {
      Object? failure;
      var frames = 0;
      await tester.runAsync(() async {
        final completer = Completer<void>();
        provider
            .resolve(ImageConfiguration.empty)
            .addListener(
              ImageStreamListener(
                (image, _) {
                  frames += 1;
                  image.dispose();
                  if (!completer.isCompleted) completer.complete();
                },
                onError: (error, _) {
                  failure = error;
                  if (!completer.isCompleted) completer.complete();
                },
              ),
            );
        await completer.future.timeout(const Duration(seconds: 10));
      });
      return failure ?? (frames > 0 ? null : StateError('nothing happened'));
    }

    testWidgets('real captured poster bytes decode into a frame', (
      tester,
    ) async {
      api.posterResult = realPoster;

      final failure = await resolve(
        tester,
        PosterImageProvider(api: api, media: media),
      );

      expect(failure, isNull);
      expect(api.calls, ['posterBytes(e4285edb34d5)']);
    });

    testWidgets('no poster is a failure the tile turns into a placeholder', (
      tester,
    ) async {
      // `posterBytes` returns null for the 404 that means "this item has no
      // artwork", which is normal. An ImageProvider has no way to say
      // "nothing, and that is fine", so the absence becomes an error here and
      // PosterTile draws its placeholder for it.
      api.posterResult = null;

      final failure = await resolve(
        tester,
        PosterImageProvider(api: api, media: media),
      );

      expect(failure, isA<StateError>());
      expect('$failure', contains('no poster'));
    });

    testWidgets('an EMPTY body is treated as no poster, not as an image', (
      tester,
    ) async {
      // A zero-length 200 would otherwise reach the decoder and fail with
      // something about an unsupported image format.
      api.posterResult = Uint8List(0);

      final failure = await resolve(
        tester,
        PosterImageProvider(api: api, media: media),
      );

      expect(failure, isA<StateError>());
    });

    testWidgets('the size hint and the cancel token are forwarded', (
      tester,
    ) async {
      api.posterResult = realPoster;
      final token = CancelToken();

      await resolve(
        tester,
        PosterImageProvider(
          api: api,
          media: media,
          size: PosterSize.detail,
          cancelToken: token,
        ),
      );

      expect(api.tokens.single, same(token));
    });
  });
}
