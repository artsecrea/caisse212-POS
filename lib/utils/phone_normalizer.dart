/// Canonical form used for the customer-dedup join key.
///
/// Strategy:
///   1. Strip every character that isn't a digit (spaces, dashes,
///      parentheses, dots, `+`).
///   2. If the remaining digits start with `00<countryCode>`, drop the
///      international prefix.
///   3. If they start with `<countryCode>`, drop it too.
///   4. If they start with a single `0`, drop it (typical local dial form).
///   5. Re-prefix with `<countryCode>`.
///
/// Examples (country code "212", Morocco):
///   "+212 600 000 000"   → "212600000000"
///   "00212 600-00-00-00" → "212600000000"
///   "0600000000"         → "212600000000"
///   "600000000"          → "212600000000"
///   "06-00-00-00-00"     → "212600000000"
///
/// Returns an empty string for an empty / whitespace-only input — callers
/// should treat that as "no normalized phone" and skip the dedup step.
String normalizePhone(String raw, {String countryCode = '212'}) {
  if (raw.isEmpty) return '';
  var d = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (d.isEmpty) return '';
  if (d.startsWith('00$countryCode')) {
    d = d.substring(2 + countryCode.length);
  } else if (d.startsWith(countryCode)) {
    d = d.substring(countryCode.length);
  }
  if (d.startsWith('0')) d = d.substring(1);
  return '$countryCode$d';
}
