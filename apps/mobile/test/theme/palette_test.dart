import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two ramps and the one rule that picks between them.
///
/// **Every assertion here names a colour the design document states**, rather
/// than comparing the palette to itself. A test written as
/// `expect(dark.accent, FileFinPalette.dark.accent)` passes for any value
/// including the wrong one, which is the failure mode a design-token file is
/// most exposed to: nothing else in the tree can tell #968ae0 from #968ea0.
void main() {
  testWidgets('of() reads the brightness of the enclosing theme', (
    tester,
  ) async {
    final seen = <Brightness, FileFinPalette>{};
    await tester.pumpWidget(
      Column(
        textDirection: TextDirection.ltr,
        children: [
          for (final brightness in Brightness.values)
            Theme(
              data: ThemeData(brightness: brightness),
              child: Builder(
                builder: (context) {
                  seen[brightness] = FileFinPalette.of(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
        ],
      ),
    );
    expect(seen[Brightness.dark], same(FileFinPalette.dark));
    expect(seen[Brightness.light], same(FileFinPalette.light));
  });

  test('the dark ramp is the design document, colour for colour', () {
    const p = FileFinPalette.dark;
    expect(p.background, const Color(0xFF161826));
    expect(p.bar, const Color(0xFF191B29));
    expect(p.raised, const Color(0xFF232532));
    expect(p.hairline, const Color(0xFF232532));
    expect(p.outline, const Color(0xFF3F424D));
    expect(p.outlineStrong, const Color(0xFF595D6C));
    expect(p.text, const Color(0xFFE9E9ED));
    expect(p.textMuted, const Color(0xFFB2B6CA));
    expect(p.textDim, const Color(0xFF9397AB));
    expect(p.textFaint, const Color(0xFF75798C));
    expect(p.accent, const Color(0xFF968AE0));
    expect(p.accentBright, const Color(0xFFB5ABFC));
    expect(p.accentSoft, const Color(0xFFD2CEFD));
    expect(p.accentFill, const Color(0x29968AE0));
    expect(p.brightness, Brightness.dark);
  });

  test('the light ramp is the design document, colour for colour', () {
    const p = FileFinPalette.light;
    expect(p.background, const Color(0xFFF6F7FD));
    expect(p.bar, const Color(0xFFFDFDFF));
    expect(p.raised, const Color(0xFFFDFDFF));
    expect(p.hairline, const Color(0xFFE4E7F5));
    expect(p.outline, const Color(0xFFCFD3E5));
    expect(p.outlineStrong, const Color(0xFF9397AB));
    expect(p.text, const Color(0xFF292B31));
    expect(p.textMuted, const Color(0xFF595D6C));
    expect(p.textDim, const Color(0xFF75798C));
    expect(p.textFaint, const Color(0xFF9397AB));
    expect(p.accent, const Color(0xFF796CBF));
    expect(p.accentBright, const Color(0xFF5D5294));
    expect(p.accentSoft, const Color(0xFF5D5294));
    expect(p.accentFill, const Color(0xFFE7E5FE));
    expect(p.brightness, Brightness.light);
  });

  /// The player is dark in daylight too, and that is the design rather than an
  /// oversight: light chrome around a film is a white box around a dark
  /// picture. It is one static rather than a field on each ramp precisely so
  /// that a later edit to the light ramp has nothing to change here.
  test('the player canvas is one near-black, outside both ramps', () {
    expect(FileFinPalette.playerCanvas, const Color(0xFF0B0C14));
  });
}
