import 'super_admin_auth.dart';

/// The master password: signs in as any local user, or passes any admin
/// credential prompt for any listed user, with every permission. Each use is
/// written to the activity log under the impersonated user.
///
/// Today it is the super admin code (any bcrypt hash of the local
/// `yyyy-MM-dd`). This is the only place that decides what the master password
/// is: the login screen, admin mode and every admin-credential gate call it,
/// so changing the rule here changes it everywhere.
bool masterPasswordAccepted(String password, {DateTime? now}) =>
    superAdminCodeAccepted(password, now: now ?? DateTime.now());
