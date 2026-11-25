/// Whether a role grants [permission]: the admin type, the exact token, or a
/// `:*` wildcard prefix ("pos:*" grants every `pos:` token, "pos:orders:*"
/// every order one).
///
/// [permissions] is the comma-separated list stored on the user.
bool roleGrants({
  required String userType,
  required String permissions,
  required String permission,
}) {
  if (userType.toLowerCase() == 'admin') return true;
  final tokens = permissions.split(',').map((p) => p.trim());
  if (tokens.contains(permission)) return true;
  for (final token in tokens) {
    if (token.endsWith(':*') &&
        permission.startsWith(token.substring(0, token.length - 1))) {
      return true;
    }
  }
  return false;
}
