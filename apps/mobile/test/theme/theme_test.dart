import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the `ThemeData` builder promises the screens below it.
///
/// The screens read colours through [FileFinPalette] directly; what they read
/// through the theme is everything Material draws **for** them — the scaffold
/// it paints, the divider it inserts, the slider it themes. Those are the ones
/// asserted here, because a screen cannot state them at its call site.
void main() {
  for (final palette in [FileFinPalette.dark, FileFinPalette.light]) {
    final name = palette.brightness.name;

    test('$name: Material draws its own surfaces from the ramp', () {
      final theme = fileFinTheme(palette);
      expect(theme.brightness, palette.brightness);
      expect(theme.scaffoldBackgroundColor, palette.background);
      expect(theme.dividerTheme.color, palette.hairline);
      expect(theme.colorScheme.primary, palette.accent);
      expect(theme.colorScheme.surface, palette.background);
      expect(theme.colorScheme.onSurface, palette.text);
      expect(theme.colorScheme.outline, palette.outline);
    });

    test('$name: body text is the ramp text colour', () {
      final theme = fileFinTheme(palette);
      expect(theme.textTheme.bodyMedium?.color, palette.text);
      expect(theme.textTheme.bodySmall?.color, palette.textMuted);
      expect(theme.textTheme.titleMedium?.fontWeight, FontWeight.w500);
    });

    test('$name: the scrubber is violet on a dim track', () {
      final theme = fileFinTheme(palette);
      expect(theme.sliderTheme.activeTrackColor, palette.accent);
      expect(theme.sliderTheme.inactiveTrackColor, palette.outline);
      expect(theme.sliderTheme.trackHeight, 4);
    });
  }

  /// The bundled family, asserted by name. A typo here degrades silently to
  /// the platform's own monospace, which looks close enough that no other
  /// assertion in the tree would notice.
  test('mono() is the bundled IBM Plex Mono, at the size asked for', () {
    final style = mono(size: 11, color: const Color(0xFF75798C));
    expect(style.fontFamily, 'IBMPlexMono');
    expect(style.fontSize, 11);
    expect(style.color, const Color(0xFF75798C));
  });

  /// `.14em` at 11px is 1.54 logical pixels. Written as a multiple of the
  /// size rather than as a literal so a size change carries the tracking with
  /// it — the design states the tracking in `em`.
  test('eyebrow() is upper-tracked mono at the size asked for', () {
    final style = eyebrow(size: 12, color: const Color(0xFFB5ABFC));
    expect(style.fontFamily, 'IBMPlexMono');
    expect(style.letterSpacing, closeTo(12 * 0.14, 0.001));
    expect(style.color, const Color(0xFFB5ABFC));
  });
}
