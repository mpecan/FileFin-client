import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

const int _threshold = 50 * 1000 * 1000;

/// One row of the exhaustive table: network, the wifi-only setting, the
/// server's transcode verdict, the file size **relative to the threshold**, and
/// the decision named literally.
///
/// The expectation is spelled out per row rather than computed, because a test
/// that recomputes the rule it is checking agrees with any rule.
typedef _Case = (NetworkType, bool, bool, int, String);

/// NetworkType(3) x wifiOnly(2) x transcode(2) x size-vs-threshold(3).
///
/// The `0` rows are the ones that matter most: they pin `>` against `>=` at the
/// threshold, which is exactly the boundary a mutant flips.
const _cases = <_Case>[
  // Offline refuses before anything else is consulted.
  (NetworkType.none, false, false, -1, 'Refuse:offline'),
  (NetworkType.none, false, false, 0, 'Refuse:offline'),
  (NetworkType.none, false, false, 1, 'Refuse:offline'),
  (NetworkType.none, false, true, -1, 'Refuse:offline'),
  (NetworkType.none, false, true, 0, 'Refuse:offline'),
  (NetworkType.none, false, true, 1, 'Refuse:offline'),
  (NetworkType.none, true, false, -1, 'Refuse:offline'),
  (NetworkType.none, true, false, 0, 'Refuse:offline'),
  (NetworkType.none, true, false, 1, 'Refuse:offline'),
  (NetworkType.none, true, true, -1, 'Refuse:offline'),
  (NetworkType.none, true, true, 0, 'Refuse:offline'),
  (NetworkType.none, true, true, 1, 'Refuse:offline'),

  // On wifi neither the wifi-only setting nor the size is consulted at all.
  (NetworkType.wifi, false, false, -1, 'PlayDirect'),
  (NetworkType.wifi, false, false, 0, 'PlayDirect'),
  (NetworkType.wifi, false, false, 1, 'PlayDirect'),
  (NetworkType.wifi, false, true, -1, 'PlayHls'),
  (NetworkType.wifi, false, true, 0, 'PlayHls'),
  (NetworkType.wifi, false, true, 1, 'PlayHls'),
  (NetworkType.wifi, true, false, -1, 'PlayDirect'),
  (NetworkType.wifi, true, false, 0, 'PlayDirect'),
  (NetworkType.wifi, true, false, 1, 'PlayDirect'),
  (NetworkType.wifi, true, true, -1, 'PlayHls'),
  (NetworkType.wifi, true, true, 0, 'PlayHls'),
  (NetworkType.wifi, true, true, 1, 'PlayHls'),

  // Metered, wifi-only on: refused whatever the size or the mode.
  (NetworkType.metered, true, false, -1, 'Refuse:wifiOnlyOnMetered'),
  (NetworkType.metered, true, false, 0, 'Refuse:wifiOnlyOnMetered'),
  (NetworkType.metered, true, false, 1, 'Refuse:wifiOnlyOnMetered'),
  (NetworkType.metered, true, true, -1, 'Refuse:wifiOnlyOnMetered'),
  (NetworkType.metered, true, true, 0, 'Refuse:wifiOnlyOnMetered'),
  (NetworkType.metered, true, true, 1, 'Refuse:wifiOnlyOnMetered'),

  // Metered, wifi-only off: the size guard, and only strictly above asks.
  (NetworkType.metered, false, false, -1, 'PlayDirect'),
  (NetworkType.metered, false, false, 0, 'PlayDirect'),
  (NetworkType.metered, false, false, 1, 'Confirm:PlayDirect'),
  (NetworkType.metered, false, true, -1, 'PlayHls'),
  (NetworkType.metered, false, true, 0, 'PlayHls'),
  (NetworkType.metered, false, true, 1, 'Confirm:PlayHls'),
];

Matcher _matcherFor(String expected, int size) => switch (expected) {
  'PlayDirect' => isA<PlayDirect>(),
  'PlayHls' => isA<PlayHls>(),
  'Refuse:offline' => isA<Refuse>().having(
    (r) => r.reason,
    'reason',
    RefuseReason.offline,
  ),
  'Refuse:wifiOnlyOnMetered' => isA<Refuse>().having(
    (r) => r.reason,
    'reason',
    RefuseReason.wifiOnlyOnMetered,
  ),
  'Confirm:PlayDirect' =>
    isA<ConfirmLargeOnMetered>()
        .having((c) => c.bytes, 'bytes', size)
        .having((c) => c.proceed, 'proceed', isA<PlayDirect>()),
  'Confirm:PlayHls' =>
    isA<ConfirmLargeOnMetered>()
        .having((c) => c.bytes, 'bytes', size)
        .having((c) => c.proceed, 'proceed', isA<PlayHls>()),
  _ => throw ArgumentError('unmapped expectation $expected'),
};

void main() {
  test('the table covers every combination exactly once', () {
    expect(_cases, hasLength(36));
    expect(_cases.toSet(), hasLength(36));
  });

  for (final (network, wifiOnly, transcode, delta, expected) in _cases) {
    final size = _threshold + delta;
    final label =
        '${network.name}/wifiOnly=$wifiOnly/transcode=$transcode/'
        'size=threshold${delta >= 0 ? '+' : ''}$delta';

    test('$label -> $expected', () {
      final decision = decide(
        // index and the other fields default; only these two are consulted.
        FileInfo(size: size, transcode: transcode),
        network,
        PlaybackSettings(wifiOnly: wifiOnly, meteredWarnBytes: _threshold),
      );
      expect(decision, _matcherFor(expected, size));
    });
  }

  test('exactly at the threshold does NOT ask — the comparison is >', () {
    // Split out of the table so it fails by name. `>` becoming `>=` is the
    // single most likely mutation in this function, and 1 byte either side of
    // the threshold is what separates a guard from a nuisance.
    const settings = PlaybackSettings(
      wifiOnly: false,
      meteredWarnBytes: _threshold,
    );
    FileInfo sized(int size) => FileInfo(size: size);

    expect(
      decide(sized(_threshold), NetworkType.metered, settings),
      isA<PlayDirect>(),
    );
    expect(
      decide(sized(_threshold + 1), NetworkType.metered, settings),
      isA<ConfirmLargeOnMetered>(),
    );
  });

  test('the confirmation carries what happens after it is accepted', () {
    // Typing `proceed` as PlayNow rather than PlaybackDecision is what keeps a
    // caller's switch exhaustive without an untestable assert: there is no
    // Refuse to handle on the far side of a confirmation.
    final decision =
        decide(
              const FileInfo(size: 900, transcode: true),
              NetworkType.metered,
              const PlaybackSettings(wifiOnly: false, meteredWarnBytes: 100),
            )
            as ConfirmLargeOnMetered;
    expect(decision.bytes, 900);
    expect(decision.proceed, isA<PlayNow>());
    expect(decision.proceed, isA<PlayHls>());
  });

  test('the mode comes from the server verdict on a captured payload', () {
    // decide() must never reimplement transcode.DirectPlayable. These two
    // fixtures are the two branches, as the real server decided them.
    const wifi = NetworkType.wifi;
    const settings = PlaybackSettings(wifiOnly: false, meteredWarnBytes: 1);

    final direct = MediaDetail.fromJson(
      loadFixture('media_detail_directplay'),
    ).files.single;
    expect(direct.transcode, isFalse);
    expect(decide(direct, wifi, settings), isA<PlayDirect>());

    final hls = MediaDetail.fromJson(
      loadFixture('media_detail_transcode'),
    ).files.first;
    expect(hls.transcode, isTrue);
    expect(decide(hls, wifi, settings), isA<PlayHls>());
  });

  test('a decision is exhaustively switchable, with no default arm', () {
    // The sealed hierarchy earns its keep only if the compiler enforces this.
    String describe(PlaybackDecision d) => switch (d) {
      PlayDirect() => 'direct',
      PlayHls() => 'hls',
      ConfirmLargeOnMetered(:final bytes) => 'confirm $bytes',
      Refuse(:final reason) => 'refuse ${reason.name}',
    };

    expect(describe(const PlayDirect()), 'direct');
    expect(describe(const PlayHls()), 'hls');
    expect(
      describe(
        const ConfirmLargeOnMetered(bytes: 12, proceed: PlayHls()),
      ),
      'confirm 12',
    );
    expect(
      describe(const Refuse(RefuseReason.offline)),
      'refuse offline',
    );
    expect(
      describe(const Refuse(RefuseReason.wifiOnlyOnMetered)),
      'refuse wifiOnlyOnMetered',
    );
  });

  test('PlaybackSettings holds exactly the two levers that exist today', () {
    const settings = PlaybackSettings(wifiOnly: true, meteredWarnBytes: 42);
    expect(settings.wifiOnly, isTrue);
    expect(settings.meteredWarnBytes, 42);
    expect(settings.copyWith(wifiOnly: false).wifiOnly, isFalse);
    expect(settings.copyWith(meteredWarnBytes: 7).meteredWarnBytes, 7);
    expect(
      settings,
      const PlaybackSettings(wifiOnly: true, meteredWarnBytes: 42),
    );
  });
}
