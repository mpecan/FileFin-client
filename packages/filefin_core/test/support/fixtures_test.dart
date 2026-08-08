import 'package:test/test.dart';

import 'fixtures.dart';

void main() {
  test('repoRoot finds the directory holding the justfile', () {
    expect(
      repoRoot().listSync().map((e) => e.path.split('/').last),
      contains('justfile'),
    );
  });

  test('loadFixture decodes a captured object payload', () {
    expect(loadFixture('state'), containsPair('version', '0.20.3'));
  });

  test('loadFixtureList decodes a captured array payload', () {
    expect(loadFixtureList('categories'), hasLength(3));
    expect(loadFixtureList('search_empty'), isEmpty);
  });

  test('fixtureText reads a non-JSON fixture verbatim', () {
    expect(fixtureText('hls_index.m3u8'), startsWith('#EXTM3U'));
  });

  test('a missing fixture fails loudly rather than decoding to nothing', () {
    expect(() => loadFixture('no_such_fixture'), throwsA(isA<Exception>()));
  });
}
