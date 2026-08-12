import 'package:flutter/material.dart';

/// The redesign's colour ramp, in the two brightnesses it was drawn in.
///
/// **An enum with fields rather than a `ThemeExtension`.** An extension would
/// buy `copyWith` and `lerp` over fifteen fields — a hundred lines of
/// boilerplate nothing in this app calls, that `just mutants` would produce
/// fifteen unkillable mutants from, and that §1 has no milestone for. Two
/// canonical values and one lookup is the whole mechanism.
///
/// **Roles, never swatch names.** [accentBright] is *the colour a small glyph
/// on a tinted surface is drawn in*; it happens to be lighter than [accent] in
/// the dark ramp and darker in the light one. Naming these `violet300` would
/// have made the light ramp read as a mistake.
enum FileFinPalette {
  /// The dark ramp — the one every TV screen and every player uses.
  dark(
    brightness: Brightness.dark,
    background: Color(0xFF161826),
    bar: Color(0xFF191B29),
    raised: Color(0xFF232532),
    hairline: Color(0xFF232532),
    outline: Color(0xFF3F424D),
    outlineStrong: Color(0xFF595D6C),
    text: Color(0xFFE9E9ED),
    textMuted: Color(0xFFB2B6CA),
    textDim: Color(0xFF9397AB),
    textFaint: Color(0xFF75798C),
    accent: Color(0xFF968AE0),
    accentBright: Color(0xFFB5ABFC),
    accentSoft: Color(0xFFD2CEFD),
    accentFill: Color(0x29968AE0),
  ),

  /// The light ramp, for a phone following the system into daylight.
  light(
    brightness: Brightness.light,
    background: Color(0xFFF6F7FD),
    bar: Color(0xFFFDFDFF),
    raised: Color(0xFFFDFDFF),
    hairline: Color(0xFFE4E7F5),
    outline: Color(0xFFCFD3E5),
    outlineStrong: Color(0xFF9397AB),
    text: Color(0xFF292B31),
    textMuted: Color(0xFF595D6C),
    textDim: Color(0xFF75798C),
    textFaint: Color(0xFF9397AB),
    accent: Color(0xFF796CBF),
    accentBright: Color(0xFF5D5294),
    accentSoft: Color(0xFF5D5294),
    accentFill: Color(0xFFE7E5FE),
  );

  const FileFinPalette({
    required this.brightness,
    required this.background,
    required this.bar,
    required this.raised,
    required this.hairline,
    required this.outline,
    required this.outlineStrong,
    required this.text,
    required this.textMuted,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.accentBright,
    required this.accentSoft,
    required this.accentFill,
  });

  /// What a video is laid on, in **both** ramps.
  ///
  /// The player is dark in daylight too: white chrome around a dark picture is
  /// a lightbox, and every reference frame in the design document draws it on
  /// this near-black. One constant rather than a field on each value, so an
  /// edit to the light ramp has nothing here to get wrong.
  static const playerCanvas = Color(0xFF0B0C14);

  /// Which ramp this is. What the theme builder hands `ThemeData`.
  final Brightness brightness;

  /// What a screen is painted on.
  final Color background;

  /// The navigation bar, the search field, the rail — chrome that must read as
  /// *behind* the content rather than on it.
  final Color bar;

  /// Chips, pressed surfaces, and the block where a poster has not arrived.
  final Color raised;

  /// The one-pixel rule between rows.
  final Color hairline;

  /// The border of a resting outlined control.
  final Color outline;

  /// The border of the same control once it matters — focused, or carrying the
  /// only affordance in its group.
  final Color outlineStrong;

  /// Body and heading text.
  final Color text;

  /// A subtitle: still meant to be read, one step back.
  final Color textMuted;

  /// A metadata line: read only when looked for.
  final Color textDim;

  /// A count, a unit, a hint. Present, not addressed.
  final Color textFaint;

  /// The brand violet: progress fills, the active tab rule, focus.
  final Color accent;

  /// A glyph or label sitting **on** [accentFill].
  final Color accentBright;

  /// Text on [accentFill] — the resume button's own words.
  final Color accentSoft;

  /// The tint behind a selected pill or the primary action.
  final Color accentFill;

  /// The ramp matching the brightness in force above [context].
  static FileFinPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
