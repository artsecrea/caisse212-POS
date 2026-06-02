import 'dart:convert';

/// Parse a user-typed string into ESC/POS bytes.
///
/// Strategy:
///   1. Strip whitespace, commas, semicolons, and `0x` prefixes.
///   2. If everything that remains is a valid hex sequence of even length,
///      interpret pairs as hex bytes — supports common copy-paste shapes
///      like `1B 40`, `0x1B,0x40`, `1B40 0A`.
///   3. Otherwise fall back to UTF-8 bytes of the original input — lets the
///      user type `Hello world\n` for quick smoke tests.
///
/// Returns an empty list for empty input.
List<int> parseEscPosInput(String raw) {
  if (raw.isEmpty) return const [];

  final cleaned = raw
      .replaceAll(RegExp(r'0[xX]'), '')
      .replaceAll(RegExp(r'[\s,;]+'), '');

  if (cleaned.isNotEmpty &&
      cleaned.length.isEven &&
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) {
    final bytes = <int>[];
    for (var i = 0; i < cleaned.length; i += 2) {
      bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  return utf8.encode(raw);
}
