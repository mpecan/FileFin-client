import 'package:filefin_mobile/src/theme/filefin_mark.dart';
import 'package:flutter/material.dart';

/// Draws one navigation destination's glyph, sized and coloured by the bar or
/// rail that owns it.
///
/// A function rather than an `IconData` because the Home destination is the
/// application mark, which is a shape and not a character in a font.
typedef NavGlyph =
    Widget Function({required Color colour, required double size});

/// A glyph drawn from [icon].
NavGlyph iconGlyph(IconData icon) =>
    ({required Color colour, required double size}) =>
        Icon(icon, size: size, color: colour);

/// The application mark, which is the Home destination on both shells.
Widget markGlyph({required Color colour, required double size}) =>
    FileFinMark(size: size, colour: colour);
