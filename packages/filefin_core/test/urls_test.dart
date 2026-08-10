import 'package:filefin_core/filefin_core.dart';
// The barrel hides `ApiPaths` — it has no consumer outside this library (§5),
// and its path literals are what `undocumented_endpoint` greps. Importing the
// private library here is what gives them a consumer and makes the §8 gate's
// dependency on their exact spelling visible in a test.
import 'package:filefin_core/src/urls.dart' show ApiPaths;
import 'package:test/test.dart';

const _id = MediaId('e4285edb34d5');
const _file = FileIndex(1);

/// Every base URL shape a self-hosted server actually turns up as.
final _bases = <String, String>{
  'bare host': 'https://media.example',
  'trailing slash': 'https://media.example/',
  'path prefix': 'https://media.example/filefin',
  'path prefix with trailing slash': 'https://media.example/filefin/',
  'non-default port': 'https://media.example:8443',
  'plain http on a LAN': 'http://192.168.1.10:8096',
};

void main() {
  group('SearchField', () {
    test('covers the whole server vocabulary, not SPEC §3.2 subset', () {
      expect(SearchField.values.map((f) => f.wire), [
        'all',
        'year',
        'decade',
        'title',
        'description',
        'cast',
        'genre',
        'tag',
        'language',
        'director',
        'writer',
      ]);
    });

    test('all is the default the server itself falls back to', () {
      expect(SearchField.all.wire, 'all');
    });
  });

  group('base URL joining', () {
    test('a trailing slash and its absence resolve identically', () {
      expect(
        FileFinUrls(Uri.parse('https://media.example/filefin/')).state,
        FileFinUrls(Uri.parse('https://media.example/filefin')).state,
      );
      expect(
        FileFinUrls(
          Uri.parse('https://media.example/filefin/'),
        ).state.toString(),
        'https://media.example/filefin/api/state',
      );
    });

    test('every base shape produces exactly one slash per boundary', () {
      final expected = <String, String>{
        'bare host': 'https://media.example/api/state',
        'trailing slash': 'https://media.example/api/state',
        'path prefix': 'https://media.example/filefin/api/state',
        'path prefix with trailing slash':
            'https://media.example/filefin/api/state',
        'non-default port': 'https://media.example:8443/api/state',
        'plain http on a LAN': 'http://192.168.1.10:8096/api/state',
      };
      for (final entry in _bases.entries) {
        expect(
          FileFinUrls(Uri.parse(entry.value)).state.toString(),
          expected[entry.key],
          reason: entry.key,
        );
      }
    });

    test('a default port is not written back into the URL', () {
      expect(
        FileFinUrls(Uri.parse('https://media.example:443')).state.toString(),
        'https://media.example/api/state',
      );
      expect(
        FileFinUrls(Uri.parse('http://media.example:80')).state.toString(),
        'http://media.example/api/state',
      );
    });

    test('a multi-segment prefix survives, and its query does not', () {
      expect(
        FileFinUrls(Uri.parse('https://h/a/b/c?stale=1#frag')).state.toString(),
        'https://h/a/b/c/api/state',
      );
    });
  });

  group('unparameterised routes', () {
    final urls = FileFinUrls(Uri.parse('https://h/filefin'));

    test('map to their documented paths', () {
      expect(urls.state.toString(), 'https://h/filefin/api/state');
      expect(urls.login.toString(), 'https://h/filefin/api/login');
      expect(urls.logout.toString(), 'https://h/filefin/api/logout');
      expect(urls.me.toString(), 'https://h/filefin/api/me');
      expect(urls.categories.toString(), 'https://h/filefin/api/categories');
      expect(urls.home.toString(), 'https://h/filefin/api/home');
      expect(urls.tags.toString(), 'https://h/filefin/api/tags');
    });
  });

  group('parameterised routes', () {
    final urls = FileFinUrls(Uri.parse('https://h'));

    test('carry their ids in the right segment', () {
      expect(
        urls.categoryMedia(const CategoryId(2)).toString(),
        'https://h/api/category/2/media',
      );
      expect(urls.mediaDetail(_id).toString(), 'https://h/api/media/$_id');
      expect(
        urls.progress(_id).toString(),
        'https://h/api/media/$_id/progress',
      );
      expect(urls.watched(_id).toString(), 'https://h/api/media/$_id/watched');
      expect(
        urls.favorite(_id).toString(),
        'https://h/api/media/$_id/favorite',
      );
      expect(urls.rating(_id).toString(), 'https://h/api/media/$_id/rating');
    });

    test('the playback family shares one file path', () {
      expect(
        urls.file(_id, _file).toString(),
        'https://h/api/media/$_id/file/1',
      );
      expect(
        urls.subtitle(_id, _file, const SubtitleIndex(2)).toString(),
        'https://h/api/media/$_id/file/1/sub/2',
      );
    });

    test('file index 0 is a real index, not an absent one', () {
      expect(
        urls.file(_id, const FileIndex(0)).toString(),
        'https://h/api/media/$_id/file/0',
      );
    });
  });

  group('poster', () {
    final urls = FileFinUrls(Uri.parse('https://h'));

    test('omits the size hint entirely when none is asked for', () {
      expect(urls.poster(_id).toString(), 'https://h/api/media/$_id/poster');
    });

    test('carries the size hint when one is', () {
      expect(
        urls.poster(_id, size: PosterSize.tile).toString(),
        'https://h/api/media/$_id/poster?size=tile',
      );
      expect(
        urls.poster(_id, size: PosterSize.detail).toString(),
        'https://h/api/media/$_id/poster?size=detail',
      );
    });
  });

  group('search', () {
    final urls = FileFinUrls(Uri.parse('https://h'));

    test('always sends both q and field, so nothing is implicit', () {
      expect(
        urls.search('bars').toString(),
        'https://h/api/search?q=bars&field=all',
      );
      expect(
        urls.search('1990s', field: SearchField.decade).toString(),
        'https://h/api/search?q=1990s&field=decade',
      );
    });

    test('lets Uri do the encoding, never string concatenation', () {
      expect(urls.search('a&b=c').query, 'q=a%26b%3Dc&field=all');
      expect(urls.search('two words').query, 'q=two+words&field=all');
      expect(
        urls.search('naïve 東京').query,
        'q=na%C3%AFve+%E6%9D%B1%E4%BA%AC&field=all',
      );
      expect(urls.search('a/b?c#d').query, 'q=a%2Fb%3Fc%23d&field=all');
    });

    test('an empty q is sent as a valueless q, which Go reads as empty', () {
      // Dart's Uri writes a parameter with an empty value as a bare `q`, with
      // no `=`. Go's url.ParseQuery reads `q` as the key `q` with the value
      // "", which is the same request. Asserted rather than normalised: this
      // is what goes on the wire.
      expect(urls.search('').toString(), 'https://h/api/search?q&field=all');
    });
  });

  test('a media id with a URL-hostile character is encoded, not injected', () {
    // MediaId is hex upstream, so this cannot happen today. It is asserted
    // because the day it can, a string-concatenated builder would produce a
    // request against a different path and the failure would look like a 404.
    expect(
      FileFinUrls(
        Uri.parse('https://h'),
      ).mediaDetail(const MediaId('a/b')).toString(),
      'https://h/api/media/a%2Fb',
    );
  });

  group('ApiPaths', () {
    /// Every route literal, unparameterised ones and parameterised ones alike.
    final all = <String>[
      ApiPaths.state,
      ApiPaths.login,
      ApiPaths.logout,
      ApiPaths.me,
      ApiPaths.categories,
      ApiPaths.home,
      ApiPaths.search,
      ApiPaths.tags,
      ApiPaths.categoryMedia(const CategoryId(2)),
      ApiPaths.mediaDetail(_id),
      ApiPaths.poster(_id),
      ApiPaths.file(_id, _file),
      ApiPaths.subtitle(_id, _file, const SubtitleIndex(2)),
      ApiPaths.progress(_id),
      ApiPaths.watched(_id),
      ApiPaths.favorite(_id),
      ApiPaths.rating(_id),
    ];

    test('every route is one absolute /api/ literal', () {
      // `_resolve` drops exactly one leading empty segment, which is only
      // correct because every path starts with `/`. Asserted rather than
      // assumed: a route written without it would lose its first segment.
      for (final path in all) {
        expect(path, startsWith('/api/'), reason: path);
        expect(path.split('/').first, isEmpty, reason: path);
      }
    });

    test('the unparameterised routes are spelled as the doc spells them', () {
      expect(ApiPaths.state, '/api/state');
      expect(ApiPaths.login, '/api/login');
      expect(ApiPaths.logout, '/api/logout');
      expect(ApiPaths.me, '/api/me');
      expect(ApiPaths.categories, '/api/categories');
      expect(ApiPaths.home, '/api/home');
      expect(ApiPaths.search, '/api/search');
      expect(ApiPaths.tags, '/api/tags');
    });
  });

  group('a segment no encoding can make safe is rejected', () {
    final urls = FileFinUrls(Uri.parse('https://h'));

    test('an empty id throws instead of addressing a shorter route', () {
      // MediaId('') is not hypothetical: it is the models' own declared
      // default, so any payload with a missing or null `id` produces one.
      // Curled live at v0.20.3, `/api/media` answered 200 text/html — the SPA
      // catch-all, a success that is not one.
      expect(() => urls.mediaDetail(const MediaId('')), throwsArgumentError);
      expect(() => urls.poster(const MediaId('')), throwsArgumentError);
      expect(() => urls.progress(const MediaId('')), throwsArgumentError);
    });

    test('a dot segment throws, because escaping it does not help', () {
      // Dart's Uri removes dot segments unconditionally, including from their
      // percent-encoded form: Uri.parse('http://h/api/media/%2E%2E/x').path is
      // '/api/x'. Rejecting the value is the only defence.
      expect(() => urls.mediaDetail(const MediaId('..')), throwsArgumentError);
      expect(() => urls.mediaDetail(const MediaId('.')), throwsArgumentError);
    });

    test('the error names the value, the parameter and the reason', () {
      // The message is asserted verbatim rather than by type. It is what a
      // developer reads when this fires, and it is also the only assertion
      // that can kill a mutant living inside it — three did, until this test
      // existed. Same reasoning as `setRating`'s RangeError bounds.
      expect(
        () => urls.mediaDetail(const MediaId('..')),
        throwsA(
          isA<ArgumentError>()
              .having((e) => e.invalidValue, 'invalidValue', '..')
              .having((e) => e.name, 'name', 'value')
              .having(
                (e) => e.message,
                'message',
                'is not a usable path segment. Uri deletes an empty segment '
                    'and the dot segments "." and "..", so the request would '
                    'address a shorter route and the SPA catch-all would '
                    'answer 200 text/html',
              ),
        ),
      );
    });

    test('escaping a dot segment by hand does not smuggle it past Uri', () {
      expect(
        Uri.parse('https://h/api/media/%2E%2E/x').path,
        '/api/x',
        reason: 'the proof that percent-encoding cannot be the fix',
      );
    });

    test('a dot inside a longer segment is untouched', () {
      // `..a` and `...` are the nearest misses to the two rejected values, and
      // neither is a dot segment.
      expect(
        urls.mediaDetail(const MediaId('..a')).toString(),
        'https://h/api/media/..a',
      );
      expect(
        urls.mediaDetail(const MediaId('...')).toString(),
        'https://h/api/media/...',
      );
    });
  });

  test('FileFinUrls compares by base, so it can be cached per server', () {
    expect(
      FileFinUrls(Uri.parse('https://h')),
      FileFinUrls(Uri.parse('https://h')),
    );
    expect(
      FileFinUrls(Uri.parse('https://h')),
      isNot(FileFinUrls(Uri.parse('https://other'))),
    );
    expect(
      FileFinUrls(Uri.parse('https://h')).hashCode,
      FileFinUrls(Uri.parse('https://h')).hashCode,
    );
    expect(
      FileFinUrls(Uri.parse('https://h')).toString(),
      contains('https://h'),
    );
  });
}
