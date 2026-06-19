import 'dart:math';

/// Character set for generated order codes: uppercase letters + digits only
/// (A–Z 0–9), e.g. `K7HG2Q9XBR`.
const String _kOrderCodeChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// Default order-code length.
const int kOrderCodeLength = 10;

final Random _rng = Random.secure();

/// Generate a short, human-readable uppercase alphanumeric order code,
/// e.g. `K7HG2Q9XBR`. With the default 10-char length over a 36-symbol
/// alphabet there are 36^10 ≈ 3.6×10^15 possibilities, so collisions are
/// vanishingly unlikely — but callers that can, should still verify the code
/// is unused (see the DB-checked variant in the waiter create-order path).
String generateOrderCode({int length = kOrderCodeLength}) {
  return String.fromCharCodes(
    Iterable.generate(
      length,
      (_) => _kOrderCodeChars.codeUnitAt(_rng.nextInt(_kOrderCodeChars.length)),
    ),
  );
}
