import 'package:bcrypt/bcrypt.dart';

/// Today's master password: the current date formatted as `YYYYMMDD`.
///
/// This is a vendor/support master key that always passes the tenant-password
/// check (e.g. when a tenant forgets their password). It rotates daily.
String masterPasswordForToday() {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y$m$d';
}

/// Verifies [input] against the tenant password (bcrypt [tenantPasswordHash])
/// OR the master password (today's date as `YYYYMMDD`).
///
/// Returns true when either matches. Used everywhere the tenant password is
/// prompted, so the master always unlocks regardless of the tenant's own password.
bool verifyTenantPassword(String input, String? tenantPasswordHash) {
  final trimmed = input.trim();

  // Master password: today's date (YYYYMMDD).
  if (trimmed.isNotEmpty && trimmed == masterPasswordForToday()) return true;

  // Tenant's own password.
  if (tenantPasswordHash == null || tenantPasswordHash.isEmpty) return false;
  try {
    return BCrypt.checkpw(trimmed, tenantPasswordHash);
  } catch (_) {
    return false;
  }
}
