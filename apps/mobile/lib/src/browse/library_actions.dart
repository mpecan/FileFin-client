import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:flutter/material.dart';

/// The header both library tabs carry: which server, and what to do about it.
///
/// **A 48-point row rather than an `AppBar`**, because the server name is not
/// a heading — it is a control that opens F11's picker, and says so by carrying
/// a caret. `AppBar.title` would put a tap target where a label is expected.
///
/// **Two glyphs where three actions live**, deliberately: the design has no
/// sign-out glyph, and sign-out is rare, destructive and must stay reachable
/// from the tab a launch lands on — so it is the second entry of the sliders
/// menu.
class LibraryHeader extends StatelessWidget implements PreferredSizeWidget {
  /// Names [title] as the server, offering whichever actions are wired.
  const LibraryHeader({
    required this.title,
    this.onServers,
    this.onSearch,
    this.onSettings,
    this.onSignOut,
    super.key,
  });

  /// The saved server's name.
  final String title;

  /// Opens F11's picker. Null leaves the chip inert but still legible.
  final VoidCallback? onServers;

  /// Jumps to the Search destination.
  final VoidCallback? onSearch;

  /// Opens the playback settings sheet.
  final VoidCallback? onSettings;

  /// Ends the session and forgets this account (F2, §9).
  final VoidCallback? onSignOut;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 14),
            _ServerChip(title: title, palette: palette, onTap: onServers),
            const Spacer(),
            if (onSearch != null)
              _HeaderButton(
                icon: Icons.search,
                tooltip: 'Search',
                palette: palette,
                onPressed: onSearch!,
              ),
            if (onSettings != null || onSignOut != null)
              _OverflowButton(
                palette: palette,
                onSettings: onSettings,
                onSignOut: onSignOut,
              ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _ServerChip extends StatelessWidget {
  const _ServerChip({
    required this.title,
    required this.palette,
    required this.onTap,
  });

  final String title;
  final FileFinPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Servers',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      // The tap target is 48 and the chip drawn inside it is the design's 32:
      // `androidTapTargetGuideline` measures the semantics node, which is the
      // `InkWell`'s box rather than the painted one.
      child: Container(
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: palette.raised,
            border: Border.all(color: palette.outline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns, size: 14, color: palette.accentBright),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.text,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down,
                size: 14,
                color: palette.textDim,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.palette,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final FileFinPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    iconSize: 20,
    color: palette.textMuted,
    icon: Icon(icon),
  );
}

/// The sliders glyph, and the two things behind it.
///
/// A menu rather than two buttons: the design allots one glyph here, and a
/// destructive action that is one tap away from a setting is a destructive
/// action people reach by accident.
class _OverflowButton extends StatelessWidget {
  const _OverflowButton({
    required this.palette,
    this.onSettings,
    this.onSignOut,
  });

  final FileFinPalette palette;
  final VoidCallback? onSettings;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    tooltip: 'More',
    iconSize: 20,
    iconColor: palette.textMuted,
    icon: const Icon(Icons.tune),
    onSelected: (action) => action(),
    itemBuilder: (_) => [
      if (onSettings case final settings?)
        PopupMenuItem(value: settings, child: const Text('Playback settings')),
      if (onSignOut case final signOut?)
        PopupMenuItem(value: signOut, child: const Text('Sign out')),
    ],
  );
}
