import 'package:filefin_mobile/src/shell/nav_glyph.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:flutter/material.dart';

/// One destination in [ShellNavBar].
@immutable
class ShellDestination {
  /// A destination drawn as [icon] when at rest and [selectedIcon] when it is
  /// the one showing, under [label].
  ShellDestination({
    required IconData icon,
    required IconData selectedIcon,
    required this.label,
  }) : glyph = iconGlyph(icon),
       selectedGlyph = iconGlyph(selectedIcon);

  /// A destination drawn as the application mark, under [label].
  ///
  /// One glyph for both states: the mark is the product's own, and an outline
  /// and a filled weight of it would read as two different logos.
  const ShellDestination.mark({required this.label})
    : glyph = markGlyph,
      selectedGlyph = markGlyph;

  /// The resting glyph.
  final NavGlyph glyph;

  /// The glyph while this destination is showing.
  final NavGlyph selectedGlyph;

  /// The word under the glyph. Also what a widget test taps.
  final String label;
}

/// The phone shell's bottom bar.
///
/// **Hand-drawn rather than a `NavigationBar`, and the reason is the
/// indicator.** Material 3 draws a filled pill *behind* the selected glyph;
/// the design draws a two-pixel rule along the *top edge* of the selected
/// third, which is a different shape in a different place and not reachable
/// through `NavigationBarThemeData`. Everything else about the bar — its
/// height, its hairline, its type sizes — is the design's too, and once the
/// indicator has to be drawn by hand the rest costs nothing to draw with it.
class ShellNavBar extends StatelessWidget {
  /// Draws [destinations], marking [selected]; a tap calls [onSelect].
  const ShellNavBar({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  /// Every destination, left to right.
  final List<ShellDestination> destinations;

  /// The index currently showing.
  final int selected;

  /// Asked to show another one.
  final ValueChanged<int> onSelect;

  /// The design's bar height, above whatever the OS reserves below it.
  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.bar,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _Destination(
                    destination: destinations[i],
                    palette: palette,
                    selected: i == selected,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.destination,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final ShellDestination destination;
  final FileFinPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            if (selected)
              Container(
                width: 34,
                height: 2,
                color: palette.accent,
              ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  (selected ? destination.selectedGlyph : destination.glyph)(
                    size: 20,
                    colour: selected ? palette.accentBright : palette.textDim,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    destination.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: selected ? palette.text : palette.textDim,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
