import 'package:flutter/widgets.dart';

/// The application mark: a film folder with a fin rising from behind its tab.
///
/// Drawn rather than shipped as an image, so the launcher icon and the glyph in
/// the navigation are the same geometry at every size and cannot drift apart.
/// One colour throughout — the folder and its front panel are tints of it, and
/// the sprocket holes and the fin's hidden base are cut straight through to
/// whatever is behind, so the mark sits on any ground.
class FileFinMark extends StatelessWidget {
  /// Draws the mark [size] across, in [colour].
  const FileFinMark({required this.size, required this.colour, super.key});

  /// Width and height. The mark is square.
  final double size;

  /// The single colour every part is a tint of.
  final Color colour;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: FileFinMarkPainter(colour: colour)),
  );
}

/// Paints [FileFinMark] into whatever rectangle it is given.
///
/// The geometry is authored in a 96x96 square and scaled to fit, so a caller
/// picks a size rather than a variant.
class FileFinMarkPainter extends CustomPainter {
  /// Paints in [colour].
  const FileFinMarkPainter({required this.colour});

  /// The single colour every part is a tint of.
  final Color colour;

  /// The side of the square the paths are authored in.
  static const _authoredSide = 96.0;

  /// Tints the folder down far enough to sit behind the fin without competing
  /// with it, while the front panel stays solid so the sprocket row reads.
  /// Below roughly 20 points the holes close up and the mark becomes a
  /// silhouette; the navigation draws it at 20 and above.
  static const _bodyOpacity = 0.34;

  /// The front panel's tint, carrying the sprocket row.
  static const _panelOpacity = 0.68;

  /// The fin, rising from behind the folder tab.
  @visibleForTesting
  static Path fin() => Path()
    ..moveTo(24, 50)
    ..cubicTo(32, 40, 46, 24, 68, 15)
    ..cubicTo(62, 26, 58, 38, 56, 50)
    ..close();

  /// The folder body, tab and all.
  @visibleForTesting
  static Path body() => Path()
    ..moveTo(12, 50)
    ..arcToPoint(const Offset(18, 44), radius: _corner)
    ..lineTo(38, 44)
    ..lineTo(44, 50)
    ..lineTo(80, 50)
    ..arcToPoint(const Offset(86, 56), radius: _corner)
    ..lineTo(86, 76)
    ..arcToPoint(const Offset(80, 82), radius: _corner)
    ..lineTo(18, 82)
    ..arcToPoint(const Offset(12, 76), radius: _corner)
    ..close();

  /// The front panel the sprocket holes are punched through.
  @visibleForTesting
  static Path panel() => Path()
    ..moveTo(12, 64)
    ..lineTo(84, 64)
    ..lineTo(84, 76)
    ..arcToPoint(const Offset(78, 82), radius: _corner)
    ..lineTo(18, 82)
    ..arcToPoint(const Offset(12, 76), radius: _corner)
    ..close();

  /// The sprocket row, cut through the panel.
  @visibleForTesting
  static Path holes() {
    final path = Path();
    for (var x = 17.0; x <= 77.0; x += 10) {
      path.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 69, 5, 5),
          const Radius.circular(1),
        ),
      );
    }
    return path;
  }

  /// Every folder corner. The arcs run clockwise, which is `arcToPoint`'s
  /// default and what makes them round outward rather than bite inward.
  static const _corner = Radius.circular(6);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _authoredSide;
    // A layer, because the folder and the sprocket row are cut out rather than
    // painted over: `BlendMode.clear` needs somewhere of its own to erase, and
    // erasing straight onto the canvas would take the background with it.
    canvas
      ..saveLayer(Offset.zero & size, Paint())
      ..scale(scale);
    final erase = Paint()..blendMode = BlendMode.clear;
    canvas
      ..drawPath(fin(), Paint()..color = colour)
      ..drawPath(body(), erase)
      ..drawPath(
        body(),
        Paint()..color = colour.withValues(alpha: _bodyOpacity),
      )
      ..drawPath(
        panel(),
        Paint()..color = colour.withValues(alpha: _panelOpacity),
      )
      ..drawPath(holes(), erase)
      ..restore();
  }

  @override
  bool shouldRepaint(FileFinMarkPainter oldDelegate) =>
      oldDelegate.colour != colour;
}
