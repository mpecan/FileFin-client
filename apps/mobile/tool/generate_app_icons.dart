import 'dart:io';
import 'dart:ui' as ui;

import 'package:filefin_mobile/src/theme/filefin_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The accent the design draws the mark in — the system's `--color-accent`,
/// which is a step away from the palette's in-app accent role.
const _markColour = Color(0xFF9184D9);

/// The tile the mark sits on. The television rail is painted the same colour,
/// so the glyph there and the icon on a home screen share a ground.
const _ground = Color(0xFF12141F);

/// The fraction of the side left clear around the mark. The design's tile is
/// 196 across with a 120 mark; this is what is left, halved.
const _inset = 0.194;

/// The legacy launcher icon's side at each density.
const _densities = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// Every iOS tile, named as `Contents.json` already expects.
const _ios = {
  'Icon-App-20x20@1x': 20,
  'Icon-App-20x20@2x': 40,
  'Icon-App-20x20@3x': 60,
  'Icon-App-29x29@1x': 29,
  'Icon-App-29x29@2x': 58,
  'Icon-App-29x29@3x': 87,
  'Icon-App-40x40@1x': 40,
  'Icon-App-40x40@2x': 80,
  'Icon-App-40x40@3x': 120,
  'Icon-App-60x60@2x': 120,
  'Icon-App-60x60@3x': 180,
  'Icon-App-76x76@1x': 76,
  'Icon-App-76x76@2x': 152,
  'Icon-App-83.5x83.5@2x': 167,
  'Icon-App-1024x1024@1x': 1024,
};

/// Writes every launcher icon from the same painter the navigation draws.
///
/// Run with `just icons`, not by the suite: it sits outside `test/` so
/// `flutter test` will not collect it, and it writes into the repository. It is
/// shaped as a test because rasterising needs a real engine.
///
/// The mark and the icon cannot drift, because there is no second copy of the
/// geometry to forget to update.
void main() {
  // `runAsync`, because rasterising needs the real event loop. Under a test's
  // fake clock the first `toImage` never completes and the run hangs rather
  // than failing.
  testWidgets('write the launcher icons', (tester) async {
    await tester.runAsync(_writeAll);
  });
}

Future<void> _writeAll() async {
  final cwd = Directory.current.path;
  final app = cwd.endsWith('apps/mobile') ? cwd : '$cwd/apps/mobile';

  for (final tile in _ios.entries) {
    await _writePng(
      File(
        '$app/ios/Runner/Assets.xcassets/AppIcon.appiconset/${tile.key}.png',
      ),
      side: tile.value,
      // iOS masks the corners itself, so each tile is a filled square.
      ground: _ground,
    );
  }

  final res = '$app/android/app/src/main/res';
  for (final density in _densities.entries) {
    await _writePng(
      File('$res/mipmap-${density.key}/ic_launcher.png'),
      side: density.value,
      ground: _ground,
    );
    // The adaptive foreground's canvas is 108dp where the legacy icon's is 48.
    // The same inset leaves the mark 66dp across, inside the 72dp a launcher
    // promises not to crop. Its ground is the separate background layer, so
    // this one is drawn on nothing.
    await _writePng(
      File('$res/mipmap-${density.key}/ic_launcher_foreground.png'),
      side: density.value * 108 ~/ 48,
    );
  }
}

Future<void> _writePng(File file, {required int side, Color? ground}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final full = Size.square(side.toDouble());
  if (ground != null) {
    canvas.drawRect(Offset.zero & full, Paint()..color = ground);
  }
  canvas
    ..translate(side * _inset, side * _inset)
    ..scale(1 - 2 * _inset);
  const FileFinMarkPainter(colour: _markColour).paint(canvas, full);
  final image = await recorder.endRecording().toImage(side, side);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(png!.buffer.asUint8List());
}
