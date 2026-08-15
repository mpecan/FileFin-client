import 'dart:ui' as ui;

import 'package:filefin_mobile/src/theme/filefin_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The application mark, checked by the pixels it puts down.
///
/// Every assertion here renders the mark over two different grounds and
/// compares. A part that is cut out reports its ground both times; a part that
/// is painted reports the same colour over either. That distinction is the
/// whole design of the thing and it survives premultiplied storage, which a
/// direct read of one buffer does not.
void main() {
  const side = 96;

  Future<List<int>> pixelsOver(Color ground) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const full = Size.square(side * 1.0);
    canvas.drawRect(Offset.zero & full, Paint()..color = ground);
    const FileFinMarkPainter(colour: Color(0xFF968AE0)).paint(canvas, full);
    final image = await recorder.endRecording().toImage(side, side);
    final data = await image.toByteData();
    return data!.buffer.asUint8List().toList();
  }

  late List<int> overBlack;
  late List<int> overWhite;

  int at(List<int> px, int x, int y) {
    final i = (y * side + x) * 4;
    return (px[i] << 24) | (px[i + 1] << 16) | (px[i + 2] << 8) | px[i + 3];
  }

  setUpAll(() async {
    overBlack = await pixelsOver(const Color(0xFF000000));
    overWhite = await pixelsOver(const Color(0xFFFFFFFF));
  });

  /// The sprocket row is the reason the folder reads as film. Painting the
  /// holes in a background colour would make the mark usable on exactly one
  /// ground; cutting them means the bar, the rail and the launcher tile all
  /// show through their own.
  test('a sprocket hole is cut through, not filled', () {
    expect(at(overBlack, 19, 71), isNot(at(overWhite, 19, 71)));
    expect(at(overBlack, 19, 71), at(overBlack, 2, 2));
    expect(at(overWhite, 19, 71), at(overWhite, 2, 2));
  });

  /// The fin's base is inside the folder's outline. It is erased there rather
  /// than drawn over, so the two read as one object instead of a fin pasted on
  /// a folder.
  ///
  /// The probe sits inside both paths at once — the folder's tab spans x 18-38
  /// from y 44, and the fin still has width there. Erased, it reports the
  /// folder's tint and the ground reaches through it; drawn over, the fin's
  /// solid colour would cover the ground and read identically on both.
  test('the fin is hidden where the folder covers it', () {
    expect(at(overBlack, 30, 47), isNot(at(overWhite, 30, 47)));
  });

  test('the fin is opaque, so it reads the same on any ground', () {
    var opaque = 0;
    for (var y = 16; y < 44; y++) {
      for (var x = 25; x < 68; x++) {
        if (at(overBlack, x, y) == at(overWhite, x, y)) opaque++;
      }
    }
    expect(opaque, greaterThan(200), reason: 'the fin should be solid');
  });

  /// The panel is a tint rather than a solid, so the ground still reaches
  /// through it. A mark that hid its ground entirely would show as a dark
  /// block on a light theme.
  test('the folder is a tint, so its ground still shows through', () {
    expect(at(overBlack, 70, 56), isNot(at(overWhite, 70, 56)));
    expect(at(overBlack, 70, 56), isNot(at(overBlack, 2, 2)));
  });

  /// The panel is a heavier tint than the folder behind it — that step is what
  /// separates the front of the folder from its body. Equal tints would read as
  /// one flat shape with holes punched in it.
  test('the front panel is a heavier tint than the body behind it', () {
    // Both inside the folder; the first is under the panel, the second is not.
    expect(at(overBlack, 48, 66), isNot(at(overBlack, 70, 56)));
    expect(at(overWhite, 48, 66), isNot(at(overWhite, 70, 56)));
  });

  test('it repaints when the colour changes and not otherwise', () {
    const painter = FileFinMarkPainter(colour: Color(0xFF968AE0));
    expect(
      painter.shouldRepaint(const FileFinMarkPainter(colour: Colors.red)),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        const FileFinMarkPainter(colour: Color(0xFF968AE0)),
      ),
      isFalse,
    );
  });

  /// A collapsed box is what a rail mid-animation hands a painter, and it
  /// needs no special case: scaling by zero draws nothing and throws nothing,
  /// which is why there is no guard in `paint` to go stale.
  testWidgets('it survives being given no room', (tester) async {
    await tester.pumpWidget(
      const Center(child: FileFinMark(size: 0, colour: Color(0xFF968AE0))),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('it fills the size it is given', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: FileFinMark(size: 24, colour: Color(0xFF968AE0))),
      ),
    );

    expect(tester.getSize(find.byType(FileFinMark)), const Size(24, 24));
  });

  /// Every coordinate in the mark, pinned without rasterising any of it.
  ///
  /// `Path.contains` and `Path.getBounds` are exact geometry, so these numbers
  /// are the same on the machine that wrote them and on the Linux runner that
  /// checks them — where a golden PNG would differ on antialiasing alone. The
  /// sample count is the area at a half-unit grid: move one control point and
  /// it moves, which is what stops the shape drifting silently.
  group('the geometry is what the design drew', () {
    int covered(Path path) {
      var n = 0;
      // Quarter offsets, so no sample lands on an integer edge the path data
      // itself uses and `contains` never has to rule on a boundary.
      for (var y = 0.25; y < 96; y += 0.5) {
        for (var x = 0.25; x < 96; x += 0.5) {
          if (path.contains(Offset(x, y))) n++;
        }
      }
      return n;
    }

    test('the fin', () {
      expect(
        FileFinMarkPainter.fin().getBounds(),
        const Rect.fromLTRB(24, 15, 68, 50),
      );
      expect(covered(FileFinMarkPainter.fin()), 2637);
    });

    test('the folder body', () {
      expect(
        FileFinMarkPainter.body().getBounds(),
        const Rect.fromLTRB(12, 44, 86, 82),
      );
      expect(covered(FileFinMarkPainter.body()), 10046);
    });

    test('the front panel', () {
      expect(
        FileFinMarkPainter.panel().getBounds(),
        const Rect.fromLTRB(12, 64, 84, 82),
      );
      expect(covered(FileFinMarkPainter.panel()), 5120);
    });

    /// Seven holes of five by five with a one-unit radius. The count is what
    /// catches a hole added, dropped, resized or moved.
    test('the sprocket row', () {
      expect(
        FileFinMarkPainter.holes().getBounds(),
        const Rect.fromLTRB(17, 69, 82, 74),
      );
      expect(covered(FileFinMarkPainter.holes()), 672);
    });
  });
}
