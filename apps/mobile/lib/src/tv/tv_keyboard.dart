import 'package:filefin_mobile/src/theme/palette.dart';
import 'package:filefin_mobile/src/tv/tv_row.dart';
import 'package:flutter/material.dart';

/// The design's on-screen keyboard: A–Z, 0–9, space and backspace.
///
/// **Thirty-six keys in a wrap rather than a QWERTY block**, which is the
/// design's arrangement and the right one for a D-pad: alphabetical order means
/// the distance to a letter is predictable, where QWERTY's is something you can
/// only learn by using it.
class TvKeyboard extends StatelessWidget {
  /// Types a character through [onKey]; [onSpace] and [onBackspace] are the
  /// two keys that are not one.
  const TvKeyboard({
    required this.onKey,
    required this.onSpace,
    required this.onBackspace,
    super.key,
  });

  /// Called with the character a key carries.
  final ValueChanged<String> onKey;

  /// Appends a space.
  final VoidCallback onSpace;

  /// Removes the last character, if there is one.
  final VoidCallback onBackspace;

  /// Every key, in the order they are drawn.
  ///
  /// Public only so a test can walk them; nothing outside this library reads
  /// it (§5, `public_member_no_consumer`).
  @visibleForTesting
  static const keys = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  @override
  Widget build(BuildContext context) {
    final palette = FileFinPalette.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in keys.split(''))
                _Key(
                  palette: palette,
                  onPressed: () => onKey(key),
                  child: Text(
                    key,
                    style: TextStyle(fontSize: 20, color: palette.textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Key(
                  palette: palette,
                  onPressed: onSpace,
                  width: double.infinity,
                  child: Text(
                    'Space',
                    style: TextStyle(fontSize: 16, color: palette.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _Key(
                palette: palette,
                onPressed: onBackspace,
                width: 88,
                child: Icon(
                  Icons.backspace_outlined,
                  size: 22,
                  color: palette.textMuted,
                  semanticLabel: 'Backspace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.palette,
    required this.onPressed,
    required this.child,
    this.width = 56,
  });

  final FileFinPalette palette;
  final VoidCallback onPressed;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) => TvFocusable(
    onSelect: onPressed,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: width,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: palette.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: child,
      ),
    ),
  );
}
