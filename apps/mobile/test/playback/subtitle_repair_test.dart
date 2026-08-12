import 'package:filefin_mobile/src/playback/subtitle_repair.dart';
import 'package:flutter_test/flutter_test.dart';

/// FileFin's converter prepends `WEBVTT` even when the body is ASS, and libmpv
/// trusts the header, parses as VTT, gets ASS, and renders nothing.
void main() {
  test('an ASS body behind a WEBVTT header loses the header', () {
    const ass = 'WEBVTT\n\n[Script Info]\nDialogue: 0,0:00:01.00';

    expect(repairSubtitle(ass), startsWith('[Script Info]'));
    expect(repairSubtitle(ass), isNot(contains('WEBVTT')));
  });

  /// Both conditions, because either alone is a file this must not touch.
  test('real WebVTT keeps its header', () {
    const vtt = 'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello';

    expect(repairSubtitle(vtt), vtt);
  });

  test('a bare ASS file with no header is left exactly as it is', () {
    const ass = '[Script Info]\nDialogue: 0,0:00:01.00';

    expect(repairSubtitle(ass), ass);
  });
}
