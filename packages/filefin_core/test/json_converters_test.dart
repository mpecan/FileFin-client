import 'package:filefin_core/filefin_core.dart';
import 'package:test/test.dart';

void main() {
  test('MediaIdConverter round-trips the wire string', () {
    const c = MediaIdConverter();
    expect(c.fromJson('e4285edb34d5'), const MediaId('e4285edb34d5'));
    expect(c.toJson(const MediaId('e4285edb34d5')), 'e4285edb34d5');
  });

  test('CategoryIdConverter round-trips the wire int, including 0', () {
    const c = CategoryIdConverter();
    expect(c.fromJson(2), const CategoryId(2));
    expect(c.toJson(const CategoryId(2)), 2);
    expect(c.fromJson(0), const CategoryId(0));
    expect(c.toJson(const CategoryId(0)), 0);
  });

  test('FileIndexConverter round-trips the wire int', () {
    const c = FileIndexConverter();
    expect(c.fromJson(1), const FileIndex(1));
    expect(c.toJson(const FileIndex(1)), 1);
  });

  test('SubtitleIndexConverter round-trips the wire int', () {
    const c = SubtitleIndexConverter();
    expect(c.fromJson(3), const SubtitleIndex(3));
    expect(c.toJson(const SubtitleIndex(3)), 3);
  });

  test('every converter is a const instance, so it can annotate a field', () {
    // json_serializable emits `const XConverter().fromJson(...)` inline, which
    // only compiles for a const constructor. A non-const converter fails at
    // codegen time with a message that does not name this cause.
    expect(const MediaIdConverter(), isA<Object>());
    expect(identical(const FileIndexConverter(), const FileIndexConverter()),
        isTrue);
  });
}
