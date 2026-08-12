import 'package:dpad/dpad.dart';
import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:flutter/material.dart';

/// One destination on [TvRail].
@immutable
class TvDestination {
  /// A destination drawn as [icon] at rest, [selectedIcon] when showing.
  const TvDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  /// The resting glyph.
  final IconData icon;

  /// The glyph while this destination is showing.
  final IconData selectedIcon;

  /// The word beside it, visible only while the rail is expanded.
  final String label;
}

/// The television's navigation: an icon rail that widens when focus enters it.
///
/// **It expands on FOCUS and not on hover, because a television has no
/// pointer.** 76 points of glyphs is enough to know where you are and not
/// enough to read; the design's answer is that arriving at the rail with the
/// D-pad is what asks for the words, so the rail widens to 208 for exactly as
/// long as focus is inside it and the content beside it does not move under the
/// cursor while a user is aiming at a poster.
class TvRail extends StatefulWidget {
  /// Draws [destinations], marking [selected]; focus moves call [onSelect].
  const TvRail({
    required this.destinations,
    required this.selected,
    required this.onSelect,
    required this.serverName,
    required this.onServers,
    super.key,
  });

  /// Every destination, top to bottom.
  final List<TvDestination> destinations;

  /// The index currently showing.
  final int selected;

  /// Asked to show another one.
  final ValueChanged<int> onSelect;

  /// Which server is signed in, on the row at the foot of the rail.
  final String serverName;

  /// Opens F11's picker.
  ///
  /// **The row carrying the server's name was not focusable until a
  /// reachability walk said so**, and `TvShell` was passing an `onServers` that
  /// nothing invoked — so on a television there was no way to switch servers or
  /// sign in to another one at all. A phone reaches the same picker by tapping
  /// the chip in its header.
  final VoidCallback onServers;

  /// How wide the rail is with only its glyphs showing.
  static const collapsedWidth = 76.0;

  /// How wide it is once focus is inside it.
  static const expandedWidth = 208.0;

  @override
  State<TvRail> createState() => _TvRailState();
}

class _TvRailState extends State<TvRail> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    // **A `Focus` that cannot take focus, NOT a `FocusScope`.** A scope is a
    // traversal boundary: `inDirection` stops at its edge, so focus entered the
    // rail and `right` never left it again — on a television that is a user
    // stranded in the navigation with no way back to the posters, and it is
    // what `tv_rail_test.dart`'s reachability walk found. `canRequestFocus:
    // false` with `skipTraversal: true` keeps the node out of the traversal
    // order entirely while `onFocusChange` still reports focus arriving
    // anywhere beneath it, which is the only thing this widget wanted.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) => setState(() => _expanded = hasFocus),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: _expanded ? TvRail.expandedWidth : TvRail.collapsedWidth,
        padding: const EdgeInsets.symmetric(vertical: 26),
        decoration: BoxDecoration(
          color: const Color(0xFF12141F),
          border: Border(right: BorderSide(color: palette.hairline)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.destinations.length; i++)
              _RailItem(
                destination: widget.destinations[i],
                palette: palette,
                selected: i == widget.selected,
                expanded: _expanded,
                onTap: () => widget.onSelect(i),
              ),
            const Spacer(),
            DpadFocusable(
              onSelect: widget.onServers,
              child: InkWell(
                onTap: widget.onServers,
                child: _RailRow(
                  icon: Icons.dns_outlined,
                  label: widget.serverName,
                  colour: palette.textFaint,
                  expanded: _expanded,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.palette,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final TvDestination destination;
  final FileFinPalette palette;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DpadFocusable(
    onSelect: onTap,
    child: Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            if (selected)
              Positioned(
                left: 0,
                top: 14,
                bottom: 14,
                child: Container(width: 3, color: palette.accent),
              ),
            _RailRow(
              icon: selected ? destination.selectedIcon : destination.icon,
              label: destination.label,
              colour: selected ? const Color(0xFFF5F4FF) : palette.textDim,
              expanded: expanded,
            ),
          ],
        ),
      ),
    ),
  );
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.icon,
    required this.label,
    required this.colour,
    required this.expanded,
  });

  final IconData icon;
  final String label;
  final Color colour;
  final bool expanded;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: Row(
      children: [
        const SizedBox(width: 20),
        Icon(icon, size: 24, color: colour),
        // `Flexible` around the label rather than an `if (expanded)`: the rail
        // animates its width, and a label that appeared only at the end would
        // overflow every frame of the animation before it did.
        if (expanded)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(fontSize: 16, color: colour),
              ),
            ),
          ),
      ],
    ),
  );
}
