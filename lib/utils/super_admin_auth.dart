import 'dart:io' show Platform;

import 'package:bcrypt/bcrypt.dart';

/// Taps on the caisse logo that open the super admin prompt.
const int kSuperAdminTapCount = 20;

/// A pause longer than this between taps starts the count again, so twenty
/// idle taps spread over a shift never add up to an unlock.
const Duration kSuperAdminTapWindow = Duration(seconds: 2);

/// Super admin mode exists on the desktop tills only.
bool get superAdminPlatformSupported =>
    Platform.isWindows || Platform.isLinux;

/// The plaintext the code must be a bcrypt hash of: the local date as
/// `yyyy-MM-dd`.
String superAdminDateKey(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-'
    '${now.month.toString().padLeft(2, '0')}-'
    '${now.day.toString().padLeft(2, '0')}';

/// Whether [code] is a bcrypt hash of today's date.
///
/// bcrypt is salted, so there is no single right answer to compare against:
/// the operator generates a fresh hash of the date anywhere ($2a, $2b and $2y
/// all verify) and the till checks it. Nothing secret lives in the app, and
/// yesterday's hash stops working at midnight.
///
/// It is not a secret in the cryptographic sense: anyone who knows the scheme
/// can generate today's code.
bool superAdminCodeAccepted(String code, {required DateTime now}) {
  final hash = code.trim();
  // Cost above 14 would freeze the till for seconds on a pasted typo.
  final m = RegExp(r'^\$2[aby]\$(\d\d)\$[./A-Za-z0-9]{53}$').firstMatch(hash);
  if (m == null) return false;
  final cost = int.parse(m.group(1)!);
  if (cost < 4 || cost > 14) return false;
  try {
    return BCrypt.checkpw(superAdminDateKey(now), hash);
  } catch (_) {
    return false;
  }
}
