import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:flutter/material.dart';

/// The one bundled family, and the only one this app ships.
///
/// **The design names Inter for the sans and IBM Plex Mono for the metadata
/// voice; only the second is bundled**, and that is a decision rather than an
/// omission. Inter's role is the platform's own UI face on both platforms
/// Flutter draws for here — Roboto on Android, SF on iOS — and both are close
/// enough to Inter that a reader would have to be told. The mono is the half
/// nothing substitutes for: Android's `monospace` alias and iOS's Menlo have
/// different widths and no shared metrics, so a mono line would be a different
/// length on each platform and the design's aligned counts and timestamps
/// would not align. 173 kB of TTF buys the one that cannot be faked.
const _monoFamily = 'IBMPlexMono';

/// The metadata voice: counts, durations, sizes, file extensions.
TextStyle mono({
  required double size,
  required Color color,
  FontWeight? weight,
}) => TextStyle(
  fontFamily: _monoFamily,
  fontSize: size,
  color: color,
  fontWeight: weight,
  height: 1.3,
);

/// A section label above a heading — mono, upper case, widely tracked.
///
/// The caller upper-cases the words; this only sets the voice. Tracking is a
/// multiple of the size because the design states it in `em`, so a size change
/// must carry it.
TextStyle eyebrow({required double size, required Color color}) => TextStyle(
  fontFamily: _monoFamily,
  fontSize: size,
  color: color,
  letterSpacing: size * 0.14,
);

/// Everything Material paints on a screen's behalf, drawn from [palette].
///
/// Deliberately small. The screens read [FileFinPalette] directly for anything
/// they draw themselves, so what belongs here is only what a widget cannot
/// state at its own call site: the scaffold's ground, the divider Material
/// inserts between rows, and the slider's track.
ThemeData fileFinTheme(FileFinPalette palette) {
  final base = ThemeData(brightness: palette.brightness, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    colorScheme: ColorScheme(
      brightness: palette.brightness,
      primary: palette.accent,
      onPrimary: palette.brightness == Brightness.dark
          ? const Color(0xFF12141F)
          : const Color(0xFFFDFDFF),
      primaryContainer: palette.accentFill,
      onPrimaryContainer: palette.accentSoft,
      secondary: palette.accentBright,
      onSecondary: palette.background,
      surface: palette.background,
      onSurface: palette.text,
      surfaceContainerHighest: palette.raised,
      onSurfaceVariant: palette.textDim,
      outline: palette.outline,
      outlineVariant: palette.hairline,
      error: const Color(0xFFE0778C),
      onError: const Color(0xFF12141F),
    ),
    dividerTheme: DividerThemeData(
      color: palette.hairline,
      space: 1,
      thickness: 1,
    ),
    iconTheme: IconThemeData(color: palette.textDim),
    textTheme: _textTheme(base.textTheme, palette),
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: palette.accent,
      inactiveTrackColor: palette.outline,
      thumbColor: palette.text,
      overlayColor: palette.accentFill,
    ),
  );
}

/// The design's type scale: 500 rather than 700 for every heading, and body
/// text one notch quieter than the headings above it.
TextTheme _textTheme(TextTheme base, FileFinPalette palette) => base.copyWith(
  headlineSmall: base.headlineSmall?.copyWith(
    color: palette.text,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
  ),
  titleLarge: base.titleLarge?.copyWith(
    color: palette.text,
    fontWeight: FontWeight.w500,
  ),
  titleMedium: base.titleMedium?.copyWith(
    color: palette.text,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  ),
  titleSmall: base.titleSmall?.copyWith(
    color: palette.text,
    fontSize: 13,
    fontWeight: FontWeight.w500,
  ),
  bodyMedium: base.bodyMedium?.copyWith(color: palette.text, fontSize: 14),
  bodySmall: base.bodySmall?.copyWith(color: palette.textMuted, fontSize: 12),
  labelLarge: base.labelLarge?.copyWith(
    color: palette.text,
    fontWeight: FontWeight.w500,
  ),
);
