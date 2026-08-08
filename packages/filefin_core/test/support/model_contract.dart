/// The three tests CLAUDE.md §8 requires of every wire model, in one place.
///
/// 1. **Round-trip** a payload captured from a real server. A hand-written JSON
///    literal that agrees with our own class proves only that we can spell our
///    own field names.
/// 2. **Tolerance** — an unknown field appears at every level of the payload,
///    including inside nested objects and inside objects in lists. Decoding
///    must not throw and must not change a single known field. This is what a
///    server upgrade looks like.
/// 3. **Omission** — every optional key is gone. Decoding must produce the
///    documented defaults rather than a null nobody checked for.
///
/// Cases 2 and 3 are what make §8 real; case 1 alone passes for a model that
/// silently drops half the payload.
library;

import 'package:test/test.dart';

/// Adds a field no version of the server has ever sent to `node` and to every
/// map nested anywhere inside it, lists included.
///
/// The injected value is deliberately a nested object holding mixed types: a
/// decoder that survives an unknown scalar can still choke on an unknown object
/// if it tries to walk what it does not recognise.
Object? withUnknownFields(Object? node) {
  if (node is Map<String, Object?>) {
    return <String, Object?>{
      for (final entry in node.entries)
        entry.key: withUnknownFields(entry.value),
      'fieldFromALaterServer': <String, Object?>{
        'nested': <Object?>[1, 'two', null, true],
      },
    };
  }
  if (node is List<Object?>) return node.map(withUnknownFields).toList();
  return node;
}

/// Runs the three-part contract for one model.
///
/// [decode] and [encode] are the model's own `fromJson`/`toJson`; [onFixture]
/// and [onDefaults] carry the assertions only that model can make.
void modelContract<T extends Object>(
  String name, {
  required Map<String, Object?> payload,
  required T Function(Map<String, Object?> json) decode,
  required Map<String, Object?> Function(T model) encode,
  required void Function(T model) onFixture,
  required void Function(T model) onDefaults,
}) {
  group(name, () {
    test('round-trips the captured payload', () {
      final decoded = decode(payload);
      onFixture(decoded);

      final reDecoded = decode(encode(decoded));
      expect(reDecoded, decoded);
      expect(reDecoded.hashCode, decoded.hashCode);
      expect(reDecoded.toString(), decoded.toString());
    });

    test('ignores unknown fields at every level', () {
      final tolerant = decode(
        withUnknownFields(payload)! as Map<String, Object?>,
      );
      expect(tolerant, decode(payload));
      onFixture(tolerant);
    });

    test('applies defaults when every optional key is absent', () {
      onDefaults(decode(const <String, Object?>{}));
    });
  });
}
