import 'dart:async' show unawaited;
import 'dart:io';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:window_manager/window_manager.dart';
import '../../data/database/app_database.dart';
import '../../providers/admin_elevation_provider.dart';
import '../../providers/database_providers.dart';
import '../../services/local_cash_session_service.dart';
import '../../services/permission_service.dart';
import '../../domain/services/day_service.dart' show ZRuleViolation;
import '../../services/local_day_service.dart';
import '../../utils/z_rule_message.dart';
import '../../services/z_rules.dart' show ZRuleBlock;
import '../../services/z_service.dart';
import '../../providers/business_day_provider.dart';
import '../../utils/admin_auth.dart';
import '../../utils/master_password.dart';
import '../../utils/password_check.dart';
import '../widgets/z_management_dialog.dart';
import '../../providers/user_provider.dart';
import '../../services/activity_log_service.dart';
import '../../utils/tenant_auth.dart';
import '../../providers/settings_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/caisse212_logo.dart';
import '../super_admin/super_admin_tap_target.dart';
import '../../services/api_service.dart';
import '../../services/notification_params.dart';
import '../../services/remote_support_service.dart';
import '../../providers/session_rules_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import '../../utils/button_styles.dart';
import '../../utils/user_display.dart';
import '../main_screen/main_screen.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../widgets/report_issue_dialog.dart';
import '../../providers/update_provider.dart';
import '../../services/update_resume_service.dart';
import '../widgets/update_dialog.dart';
import '../widgets/adaptive_text_field.dart';
import '../widgets/session_expiry_notice.dart';
import '../widgets/subscription_notice.dart';
import '../widgets/account_block_notice.dart';
import '../widgets/kick_notice_card.dart';
import '../widgets/keypad_lab_screen.dart';
import '../widgets/test_mode_screen.dart';
import '../../utils/snackbar_helper.dart';


class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  // ── Form state ─────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _startingBalanceController = TextEditingController(text: '0.0');

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isFullScreen = false;
  bool _isTogglingFullscreen = false;
  String? _errorMessage;
  String? _appVersion;
  List<User> _availableUsers = [];
  String? _selectedUsername;

  // ── Animations ─────────────────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final AnimationController _shakeCtrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _brandSlide;
  late final Animation<double> _brandFade;
  late final Animation<Offset> _formSlide;
  late final Animation<double> _formFade;
  late final Animation<double> _shakeAnim;

  // ── Date-based config password ─────────────────────────────────────────────
  String get _configPassword {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadUsers();
    _loadVersion();
    _checkFullScreenStatus();
    _entranceCtrl.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Back from an update restart: straight onto the cashier's session.
      unawaited(_resumeAfterUpdate());
      // Daily re-check while the subscription warning is up, so a renewal
      // clears the banner the next time the till is opened. Warning only: an
      // expired subscription never locks the till.
      unawaited(ref
          .read(apiServiceProvider)
          .refreshSubscription(onlyIfDue: true));
    });
  }

  void _setupAnimations() {
    _entranceCtrl = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _shakeCtrl = AnimationController(
      duration: const Duration(milliseconds: 420),
      vsync: this,
    );

    _logoScale = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 0.28, curve: Curves.easeIn),
      ),
    );
    _brandSlide = Tween<Offset>(
      begin: const Offset(-0.25, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.1, 0.65, curve: Curves.easeOutCubic),
      ),
    );
    _brandFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.1, 0.55, curve: Curves.easeIn),
      ),
    );
    _formSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
      ),
    );
    _formFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.2, 0.7, curve: Curves.easeIn),
      ),
    );

    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -14.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -14.0, end: 14.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 14.0, end: -10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: 0.0), weight: 1),
    ]).animate(_shakeCtrl);
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _shakeCtrl.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _startingBalanceController.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────

  Future<void> _loadUsers() async {
    try {
      final users = await ref.read(userRepositoryProvider).getAllUsers();
      if (!mounted) return;
      setState(() {
        _availableUsers = users;
        // A sync can delete or rename the selected user; the dropdown asserts
        // if its value is missing from the items.
        if (_selectedUsername != null &&
            !users.any((u) => u.username == _selectedUsername)) {
          _selectedUsername = null;
          _usernameController.clear();
        }
      });
    } catch (e) {
      debugPrint('Error loading users: $e');
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = 'v${info.version}');
    } catch (_) {}
  }

  Future<void> _checkFullScreenStatus() async {
    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        final isFullScreen = await windowManager.isFullScreen();
        if (mounted) setState(() => _isFullScreen = isFullScreen);
      }
    } catch (_) {}
  }

  Future<void> _toggleFullScreen() async {
    if (_isTogglingFullscreen) return;
    setState(() => _isTogglingFullscreen = true);
    try {
      final newState = !_isFullScreen;
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        // NOTE: waitUntilReadyToShow() is an init-only API — calling it on every
        // toggle pokes the window's "ready" lifecycle and is a known cause of
        // post-fullscreen pointer/layout desync on Windows. Don't call it here.
        await windowManager.setFullScreen(newState);
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _isFullScreen = newState;
                _isTogglingFullscreen = false;
              });
            }
          });
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        if (newState) {
          await SystemChrome.setEnabledSystemUIMode(
              SystemUiMode.immersiveSticky);
        } else {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
        if (mounted) {
          setState(() {
            _isFullScreen = newState;
            _isTogglingFullscreen = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error toggling fullscreen: $e');
      if (mounted) {
        setState(() {
          _isFullScreen = !_isFullScreen;
          _isTogglingFullscreen = false;
        });
      }
    }
  }

  // ── Server config dialog ───────────────────────────────────────────────────

  Future<void> _showServerConfig() async {
    final passwordController = TextEditingController();
    final verified = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool obscurePassword = true;
        return StatefulBuilder(
          builder: (context, setState) {
            final l10n = AppLocalizations.of(context)!;
            return AlertDialog(
              title: Text(l10n.translate('server_configuration')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.translate('enter_password')),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.translate('password'),
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => obscurePassword = !obscurePassword),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.translate('cancel')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final password = passwordController.text.trim();
                    Navigator.of(context).pop(password == _configPassword);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: Text(l10n.translate('verify')),
                ),
              ],
            );
          },
        );
      },
    );
    // Not disposed: the closing dialog still rebuilds its field with this controller for a few frames. It is collected with the dialog.

    if (verified != true) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        SnackBarHelper.showToast(l10n.translate('invalid_password_date'), kind: ToastKind.error);
      }
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final prefs = ref.read(sharedPreferencesProvider);
    final serverUrl =
        prefs.getString('server_url') ?? l10n.translate('not_set');
    final demoMode = prefs.getBool('demo_mode') ?? false;

    await showDialog(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(l10n.translate('server_configuration')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.translate('current_configuration'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              _buildConfigRow('${l10n.translate('server_url')}:', serverUrl),
              const SizedBox(height: 8),
              _buildConfigRow('${l10n.translate('demo_mode')}:',
                  demoMode ? l10n.translate('yes') : l10n.translate('no')),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: cs.outline.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: cs.onSecondaryContainer, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.translate('to_change_server_logout'),
                        style: TextStyle(
                            color: cs.onSecondaryContainer, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: AppButtonStyles.elevatedButtonStyle(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                isLarge: true,
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConfigRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  // ── Exit to tenant ─────────────────────────────────────────────────────────

  Future<void> _handleExitToTenant() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final tenantPasswordHash = prefs.getString('tenant_password_hash');
    final l10n = AppLocalizations.of(context)!;

    if (tenantPasswordHash == null) {
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/tenant', (route) => false);
          }
        });
      }
      return;
    }

    final passwordController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool obscurePassword = true;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(l10n.translate('exit_to_tenant')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.translate('enter_password')),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: l10n.translate('tenant_password'),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => obscurePassword = !obscurePassword),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: AppButtonStyles.textButtonStyle(isLarge: true),
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: () {
                  final password = passwordController.text.trim();
                  final verified = verifyTenantPassword(password, tenantPasswordHash);
                  Navigator.of(context).pop(verified);
                },
                style: AppButtonStyles.elevatedButtonStyle(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  isLarge: true,
                ),
                child: Text(l10n.translate('verify')),
              ),
            ],
          ),
        );
      },
    );
    // Not disposed: the closing dialog still rebuilds its field with this controller for a few frames. It is collected with the dialog.

    if (result == true) {
      final apiService = ApiService(prefs);
      await apiService.clearAuthData();
      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/tenant_login', (route) => false);
          }
        });
      }
    } else if (result == false) {
      if (mounted) {
        SnackBarHelper.showToast(l10n.translate('invalid_tenant_password'), kind: ToastKind.error);
      }
    }
  }

  // ── Sync ───────────────────────────────────────────────────────────────────

  Future<void> _handleSync() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);
      final syncService =
          ref.read(dataSyncServiceFactoryProvider)(apiService, prefs);
      if (mounted) {
        SnackBarHelper.showToast(l10n.translate('syncing_data'), kind: ToastKind.info, duration: const Duration(seconds: 2));
      }
      await syncService.syncAllData();
      // Sync session rules in the background (best-effort — 404 is fine).
      final rules = await syncService.syncSessionRules();
      if (rules != null && mounted) {
        ref.read(sessionRulesProvider.notifier).updateRules(rules);
      }
      await _loadUsers();
      if (mounted) {
        SnackBarHelper.showToast(l10n.translate('sync_complete'), kind: ToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast('${l10n.translate('sync_error')}: $e', kind: ToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Login ──────────────────────────────────────────────────────────────────

  /// Tenant, business or terminal deactivated in the back office: no sign-in
  /// until the server says it is active again (user ruling 2026-11-16). The
  /// subscription never locks; it only warns.
  bool get _accountLocked => ref.read(accountBlockProvider) != null;

  Future<void> _handleLogin() async {
    // The button's onPressed is bound at build time, so a double tap (or
    // Enter + tap) inside one frame reached here twice and opened two
    // sessions 1 ms apart.
    if (_isLoading) return;
    if (_accountLocked) {
      setState(() => _errorMessage =
          AppLocalizations.of(context)!.translate('account_locked_login'));
      _shakeCtrl.forward(from: 0);
      return;
    }
    if (_selectedUsername == null || _selectedUsername!.isEmpty) {
      setState(() => _errorMessage =
          AppLocalizations.of(context)!.translate('username_required'));
      _shakeCtrl.forward(from: 0);
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(() => _errorMessage =
          AppLocalizations.of(context)!.translate('password_required'));
      _shakeCtrl.forward(from: 0);
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userRepository = ref.read(userRepositoryProvider);
      final users = await userRepository.getAllUsers();
      if (users.isEmpty) {
        if (mounted) {
          await _performFullLogout(
              'Database is empty. Please reconnect to server or use demo mode.');
        }
        return;
      }

      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      final user = await userRepository.findByUsername(username);

      if (user == null) {
        setState(() {
          _errorMessage = l10n.translate('user_not_found');
          _isLoading = false;
        });
        _shakeCtrl.forward(from: 0);
        return;
      }

      final hash = user.password;
      final verified = BCrypt.checkpw(password, hash);

      // The synced hash above is checked bare on purpose: a malformed one
      // surfaces as an error instead of falling through to the others.
      final customVerified = !verified &&
          bcryptMatches(password,
              ref.read(sharedPreferencesProvider)
                  .getString(customPasswordKey(user.id)));

      // Checked last: the master password only matters when the user's own
      // password did not match.
      final viaMaster =
          !verified && !customVerified && masterPasswordAccepted(password);

      if (!verified && !customVerified && !viaMaster) {
        setState(() {
          _errorMessage = l10n.translate('invalid_password_try_again');
          _isLoading = false;
        });
        _shakeCtrl.forward(from: 0);
        return;
      }

      // Z gate. Decided here — after the password is verified but BEFORE any
      // state is set — so a login the Z rules refuse leaves the app cleanly
      // logged out. Inside the session try/catch below, currentUser would
      // already be set and a login audit row written.
      final zGate = await _resolveZForLogin(user, superAdmin: viaMaster);
      if (!zGate.ok) return;

      ref.read(currentUserProvider.notifier).state =
          CurrentUser.fromUser(user);
      // New session — never inherit a prior user's admin-mode elevation. A
      // master-password sign-in starts elevated: every permission, under the
      // impersonated user's name.
      ref.read(adminElevationProvider.notifier).state = viaMaster
          ? AdminElevation(
              adminId: user.id,
              adminUsername: user.username,
              viaMasterPassword: true)
          : null;

      // Record the login time so the users table shows an accurate last login.
      try {
        await ref.read(userRepositoryProvider).updateLastLogin(user.id);
      } catch (_) {}

      // Audit log uses the legal full name; the dropdown above and the
      // rest of the UI use displayLabel for friendliness.
      final actorName = '${user.firstName} ${user.lastName}'.trim();
      if (viaMaster) {
        await ref.read(activityLogServiceProvider)
            .logMasterPasswordLogin(userId: user.id, username: actorName);
      } else {
        await ref.read(activityLogServiceProvider)
            .logLogin(userId: user.id, username: actorName);
      }

      try {
        final sessionService = ref.read(sessionServiceProvider);
        final startingBalance =
            double.tryParse(_startingBalanceController.text) ?? 0.0;

        final zService = ref.read(zServiceProvider);
        ref.read(currentZProvider.notifier).state = zGate.z;

        final existingSession =
            await sessionService.getActiveSession(user.id);

        if (existingSession != null) {
          if (existingSession.status == 'paused') {
            await ref
                .read(cashSessionServiceProvider)
                .resume(existingSession.id);
            final resumedSession =
                await sessionService.getSessionById(existingSession.id);
            ref.read(currentSessionProvider.notifier).state = resumedSession;
            await ref.read(activityLogServiceProvider)
                .logSessionResume(userId: user.id, username: actorName);
            if (mounted) {
              SnackBarHelper.showToast(l10n
                    .translate('resumed_session')
                    .replaceAll('{0}', existingSession.id.toString()), kind: ToastKind.success);
            }
          } else {
            ref.read(currentSessionProvider.notifier).state = existingSession;
          }
        } else {
          // Enforce session-open rules (admin users are exempt).
          final rules = ref.read(sessionRulesProvider);
          final isAdmin = viaMaster || user.type.toLowerCase() == 'admin';
          await sessionService.checkOpenRules(
            rules,
            isAdmin: isAdmin,
            cashierId: user.id,
            moneyAtStart: startingBalance,
          );

          var newSession = await sessionService.startSession(
            cashierId: user.id,
            moneyAtStart: startingBalance,
            posId: ref.read(apiServiceProvider).getPosId(),
            // Each cashier brings their own float for now; nothing carries
            // over from the previous session.
            moneyEntered: startingBalance,
          );
          // Attach BEFORE the first push: the session carries its Z label
          // (and, as the Z's first session, its open mode) to the server.
          final z = zGate.z;
          if (z != null) {
            await zService.attachSession(newSession.id, z.id);
            newSession = (await sessionService.getSessionById(newSession.id))!;
          }
          ref.read(currentSessionProvider.notifier).state = newSession;
          // Push the new session to the server immediately (best-effort).
          // If offline, isSynced stays false and syncSessionsBulk covers it later.
          try {
            final prefs = ref.read(sharedPreferencesProvider);
            await ref
                .read(dataSyncServiceFactoryProvider)(ApiService(prefs))
                .syncSingleSession(newSession.id);
          } catch (_) {}
          await ref.read(activityLogServiceProvider)
              .logSessionStart(userId: user.id, username: actorName);
          // Fire-and-forget: notify admin devices that a session was opened.
          unawaited(ref.read(notificationOutboxProvider).send(
            'POS_SESSION_OPENED',
            NotificationParams.sessionOpened(
              terminalName: ref.read(apiServiceProvider).getPosName() ?? '',
              cashierName: actorName,
              cashierId: user.id,
              openedAt: newSession.startedAt,
              startingBalance: startingBalance,
              currency: ref.read(settingsProvider).currency,
            ),
            refId: newSession.id.toString(),
          ));
          if (mounted) {
            SnackBarHelper.showToast(l10n
                  .translate('started_new_session')
                  .replaceAll('{0}', newSession.id.toString()), kind: ToastKind.info);
          }
        }

      } catch (e) {
        Logger.instance.error('Session error: $e');
        if (mounted) {
          SnackBarHelper.showToast(l10n
                .translate('session_error')
                .replaceAll('{0}', e.toString()), kind: ToastKind.warning);
        }
        // Session setup failed — do not navigate to main with a null session.
        return;
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            // Named, so flows that return to the till can find it.
            settings: const RouteSettings(name: '/main'),
            builder: (_) => const MainScreen()));
      }
    } catch (e) {
      setState(() {
        _errorMessage = errorText(e, AppLocalizations.of(context)!);
        _isLoading = false;
      });
      _shakeCtrl.forward(from: 0);
    }

    setState(() => _isLoading = false);
  }

  Future<void> _performFullLogout(String message) async {
    try {
      final shouldLogout = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Database Error'),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: AppButtonStyles.elevatedButtonStyle(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                isLarge: true,
              ),
              child: const Text('Reconnect'),
            ),
          ],
        ),
      );
      if (shouldLogout != true) return;

      ref.read(currentUserProvider.notifier).state = null;
      ref.read(currentSessionProvider.notifier).state = null;
      // Drop the active Z too — clearAllData wipes the zs table below, so a
      // lingering in-memory Z would point at a deleted row.
      ref.read(currentZProvider.notifier).state = null;

      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);
      await apiService.logout();
      await apiService.clearAllAuthData();

      final syncService = ref.read(dataSyncServiceFactoryProvider)(apiService);
      await syncService.dumpDatabaseBeforeClear();
      await syncService.clearAllData();

      if (mounted) {
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/tenant', (route) => false);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast('Can\'t logout: please check your username and password', kind: ToastKind.error);
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isWide = MediaQuery.sizeOf(context).width >= 860;

    // A mandatory update finished downloading while nobody is signed in.
    ref.listen<UpdateState>(updateProvider, (prev, next) {
      if (next.updateRequired &&
          next.updateReady &&
          !(prev?.updateRequired == true && prev?.updateReady == true)) {
        _offerMandatoryUpdate();
      }
    });

    return Scaffold(
      body: isWide
          ? _buildWideLayout(context, l10n)
          : _buildCompactLayout(context, l10n),
    );
  }

  /// Mandatory updates wait for the login screen — after a logout nobody is
  /// mid-order — and are never pushed while someone works.
  void _offerMandatoryUpdate() {
    final update = ref.read(updateProvider);
    if (!mounted || !update.updateRequired || !update.updateReady) return;
    showUpdateDialog(context, isMandatory: true);
  }

  Future<void> _resumeAfterUpdate() async {
    // A disabled account does not get carried back into a shift by a restart.
    if (_accountLocked) return;
    if (!await UpdateResume.tryRestore(ref.read)) {
      _offerMandatoryUpdate();
      return;
    }
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    SnackBarHelper.showToast(l10n.translate('update_session_resumed'),
        kind: ToastKind.success);
    Navigator.of(context).pushReplacement(MaterialPageRoute(
        settings: const RouteSettings(name: '/main'),
        builder: (_) => const MainScreen()));
  }

  // ── Wide layout (desktop / landscape tablet) ───────────────────────────────

  Widget _buildWideLayout(BuildContext context, AppLocalizations l10n) {
    final bg = Theme.of(context).scaffoldBackgroundColor;

    return Stack(
      children: [
        Row(
          children: [
            // Brand panel
            Expanded(
              flex: 4,
              child: _AnimatedPanel(
                slideAnim: _brandSlide,
                fadeAnim: _brandFade,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFFF5A369),
                        Color(0xFFF59660),
                        Color(0xFFF48655),
                        Color(0xFFF07041),
                      ],
                      stops: [0.0, 0.33, 0.67, 1.0],
                    ),
                  ),
                  child: Center(
                    child: SuperAdminTapTarget(
                      child: SvgPicture.asset(
                        'assets/images/logo-white.svg',
                        width: 360,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Form panel
            Expanded(
              flex: 6,
              child: _AnimatedPanel(
                slideAnim: _formSlide,
                fadeAnim: _formFade,
                child: Container(
                  color: bg,
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 64, vertical: 48),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: _buildFormContent(context, l10n,
                            showLogo: false),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Overlay buttons. Exit sits over the colored brand panel (onBrand);
        // action bar sits over the form panel's neutral background, so it
        // needs the surface-tinted variant to keep contrast in light themes.
        Positioned(
          top: 12,
          left: 12,
          child: _buildExitButton(onBrand: true),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _buildActionBar(context, onBrand: false),
        ),
      ],
    );
  }

  // ── Compact layout (mobile / portrait tablet) ──────────────────────────────

  Widget _buildCompactLayout(BuildContext context, AppLocalizations l10n) {
    final primary = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary,
                primary.withValues(alpha: 0.68),
              ],
            ),
          ),
        ),
        // Decorative circle
        Positioned(
          top: -60,
          right: -60,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
        ),
        Positioned(
          bottom: -80,
          left: -40,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ),
        _AnimatedPanel(
          slideAnim: _formSlide,
          fadeAnim: _formFade,
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(20, 72, 20, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Card(
                    elevation: 12,
                    shadowColor: Colors.black26,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                      child: _buildFormContent(context, l10n,
                          showLogo: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Both sit over the colored gradient → onBrand=true.
        Positioned(
            top: 12, left: 12, child: _buildExitButton(onBrand: true)),
        Positioned(
            top: 12, right: 12, child: _buildActionBar(context, onBrand: true)),
      ],
    );
  }


  // ── Form content ─────────────────────────────────────────────────────────────

  Widget _buildFormContent(
    BuildContext context,
    AppLocalizations l10n, {
    required bool showLogo,
  }) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLogo) ...[
            Center(
              child: FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: const SuperAdminTapTarget(
                    child: Caisse212Logo(size: 80),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            l10n.translate('sign_in'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Center(child: _ZDayChip()),
          const SizedBox(height: 20),

          // ── Sign-in expiry warning ────────────────────────────────────────
          // Above the form, because it is about whether this till will work
          // next week rather than about the login being attempted now. Draws
          // nothing until the last seven days, and steps aside inside the last
          // day when the blocking gate takes over.
          const AccountBlockNotice(),
          const KickNoticeCard(),
          const SessionExpiryNotice(),
          const SubscriptionNotice(),

          // ── User selector ─────────────────────────────────────────────────
          _buildUserSelector(l10n),

          const SizedBox(height: 24),

          // ── Password field ────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (context, child) => Transform.translate(
              offset: Offset(_shakeAnim.value, 0),
              child: child,
            ),
            child: _buildPasswordField(l10n),
          ),

          const SizedBox(height: 16),

          // ── Starting balance ──────────────────────────────────────────────
          // Pre-filled with '0.0' in the controller, so the hint is suppressed
          // to avoid the visible "0.0  0.0" double-render that read like a bug.
          AdaptiveKeyboardTextField(
            controller: _startingBalanceController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _isLoading ? null : _handleLogin(),
            decoration: InputDecoration(
              labelText: l10n.translate('starting_balance'),
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 18),
            ),
            style: const TextStyle(fontSize: 16),
          ),

          // ── Error banner ──────────────────────────────────────────────────
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: _shakeAnim,
              builder: (context, child) => Transform.translate(
                offset: Offset(_shakeAnim.value, 0),
                child: child,
              ),
              child: _ErrorBanner(message: _errorMessage!),
            ),
          ],

          const SizedBox(height: 28),

          // ── Login button ──────────────────────────────────────────────────
          SizedBox(
            height: 60,
            child: ElevatedButton(
              onPressed: _isLoading || ref.watch(accountBlockProvider) != null
                  ? null
                  : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF07041),
                foregroundColor: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Theme.of(context).colorScheme.onPrimary),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.login_rounded, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          l10n.translate('sign_in'),
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
            ),
          ),

          // Bench for the numeric keypad, which is not wired into any real
          // screen yet. `kReleaseMode` keeps it out of what ships — the tree
          // shaker drops the whole branch, so the lab never reaches a till.
          if (!kReleaseMode) ...[
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const KeypadLabScreen()),
                ),
                icon: const Icon(Icons.dialpad, size: 18),
                label: const Text('Keypad lab (debug)'),
              ),
            ),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TestModeScreen()),
                ),
                icon: const Icon(Icons.science_outlined, size: 18),
                label: const Text('Test mode (debug)'),
              ),
            ),
          ],

          if (_appVersion != null) ...[
            const SizedBox(height: 16),
            Text(
              _appVersion!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.38),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUserSelector(AppLocalizations l10n) {
    return DropdownButtonFormField<String>(
      // Rebuild the field's internal state when a sync changes the user list.
      key: ValueKey(_availableUsers.map((u) => u.username).join('|')),
      value: _selectedUsername,
      decoration: InputDecoration(
        labelText: '${l10n.translate('username')} *',
        prefixIcon: const Icon(Icons.person_outline),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      hint: _availableUsers.isEmpty
          ? Text(l10n.translate('loading_users'))
          : null,
      items: _availableUsers.map((user) {
        return DropdownMenuItem<String>(
          value: user.username,
          child: Text(user.displayLabel),
        );
      }).toList(),
      onChanged: _availableUsers.isEmpty
          ? null
          : (val) {
              if (val != null) {
                setState(() {
                  _selectedUsername = val;
                  _usernameController.text = val;
                  _errorMessage = null;
                });
              }
            },
    );
  }

  Widget _buildPasswordField(AppLocalizations l10n) {
    return AdaptiveKeyboardTextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      decoration: InputDecoration(
        labelText: '${l10n.translate('password')} *',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(
              _obscurePassword ? Icons.visibility : Icons.visibility_off),
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      ),
      style: const TextStyle(fontSize: 16),
    );
  }

  // ── Overlay buttons ────────────────────────────────────────────────────────

  Widget _buildExitButton({bool onBrand = true}) {
    final l10n = AppLocalizations.of(context)!;
    return _GlassButton(
      onTap: _handleExitToTenant,
      onBrand: onBrand,
      tooltip: l10n.translate('exit_to_tenant'),
      child: const Icon(Icons.exit_to_app),
    );
  }

  Future<void> _openRemoteSupport() async {
    final missing =
        AppLocalizations.of(context)!.translate('remote_support_missing');
    if (!await RemoteSupportService.launch()) {
      SnackBarHelper.showToast(missing, kind: ToastKind.error);
    }
  }

  Widget _buildActionBar(BuildContext context, {bool onBrand = true}) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final langBg = onBrand
        ? Colors.black38
        : cs.surfaceContainerHighest.withValues(alpha: 0.85);
    final langIconColor = onBrand ? Colors.white : cs.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassButton(
          onTap: _isTogglingFullscreen ? null : _toggleFullScreen,
          onBrand: onBrand,
          tooltip: l10n.translate('tooltip_fullscreen'),
          child: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
        ),
        const SizedBox(width: 6),
        _GlassButton(
          onTap: _isLoading ? null : _handleSync,
          onBrand: onBrand,
          tooltip: l10n.translate('tooltip_sync'),
          child: const Icon(Icons.sync),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: l10n.translate('tooltip_language'),
          child: Material(
            color: langBg,
            borderRadius: BorderRadius.circular(12),
            child: PopupMenuButton<String>(
              onSelected: (code) =>
                  ref.read(settingsProvider.notifier).setLanguage(code),
              itemBuilder: (_) => [
                _langItem('en', '🇬🇧', 'English'),
                _langItem('fr', '🇫🇷', 'Français'),
                _langItem('ar', '🇲🇦', 'العربية'),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.language, size: 24, color: langIconColor),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _GlassButton(
          onTap: _showServerConfig,
          onBrand: onBrand,
          tooltip: l10n.translate('tooltip_server_config'),
          child: const Icon(Icons.settings),
        ),
        const SizedBox(width: 6),
        _GlassButton(
          onTap: () => showDialog(
            context: context,
            builder: (_) => const ReportIssueDialog(),
          ),
          onBrand: onBrand,
          tooltip: l10n.translate('tooltip_report_issue'),
          child: const Icon(Icons.bug_report),
        ),
        if (RemoteSupportService.available) ...[
          const SizedBox(width: 6),
          _GlassButton(
            onTap: _openRemoteSupport,
            onBrand: onBrand,
            tooltip: l10n.translate('remote_support'),
            child: const Icon(Icons.support_agent),
          ),
        ],
        // Z (shift) management — admin/manager, works pre-login.
        //
        // Shown whether or not Z tracking is switched on. That setting governs
        // whether this terminal RUNS a Z lifecycle (day locks, forced closes);
        // it was never meant to decide whether an admin may reach the Z screen
        // at all, and hiding the button left a shop that had not enabled Z
        // with no way in — including no way to enable it from here. The dialog
        // behind it still demands admin (or pos:z:open) credentials.
        const SizedBox(width: 6),
        _GlassButton(
          onTap: _handleManageZ,
          onBrand: onBrand,
          tooltip: l10n.translate('manage_z'),
          child: const Icon(Icons.point_of_sale),
        ),
      ],
    );
  }

  /// The Z a login's new session will join, decided before anything is set.
  ///
  /// A cashier resuming their own session keeps that session's Z. Otherwise
  /// the terminal's counter is resumed from the server (or, offline, from its
  /// own sessions) and a new Z opens if the rules allow it. With
  /// `zOpenMode: MANUAL`, a user who holds `pos:z:open` is offered to open it
  /// on the spot; anyone else is refused with the rule's reason.
  Future<({bool ok, Z? z})> _resolveZForLogin(User user,
      {bool superAdmin = false}) async {
    final l10n = AppLocalizations.of(context)!;
    final active =
        await ref.read(sessionServiceProvider).getActiveSession(user.id);
    if (active != null) {
      final z = active.zId == null
          ? null
          : await ref.read(zServiceProvider).getById(active.zId!);
      return (ok: true, z: z);
    }

    final days = ref.read(dayServiceProvider);
    await days.refreshConfig();
    try {
      return (
        ok: true,
        z: await days.ensureForSession(user: user, superAdmin: superAdmin)
      );
    } on ZRuleViolation catch (refused) {
      var v = refused;
      if (v.block == ZRuleBlock.manualOpenRequired &&
          (superAdmin || userHasPermission(user, Permissions.zOpen)) &&
          mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.translate('open_z')),
            content: Text(l10n.translate('z_open_now_prompt')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.translate('open_z')),
              ),
            ],
          ),
        );
        if (go == true) {
          try {
            final z = await days.openManually(
              userId: user.id,
              hasOpenPermission: true,
              hasOverride: superAdmin ||
                  userHasPermission(user, Permissions.zOverride),
            );
            return (ok: true, z: z);
          } on ZRuleViolation catch (v2) {
            v = v2;
          }
        }
      }
      if (mounted) {
        setState(() {
          _errorMessage = v.message(l10n);
          _isLoading = false;
        });
        _shakeCtrl.forward(from: 0);
      }
      return (ok: false, z: null);
    }
  }

  /// Login-screen "Manage Z" flow: credential gate (admin OR Z-permission
  /// holder), then the Z management dialog.
  Future<void> _handleManageZ() async {
    final l10n = AppLocalizations.of(context)!;
    final elevation = await showAdminCredentialDialog(
      context,
      ref,
      title: l10n.translate('manage_z'),
      description: l10n.translate('enter_admin_credentials'),
      permission: Permissions.zOpen,
    );
    if (elevation == null || !mounted) return;
    await showZManagementDialog(context, ref, elevation);
  }

  PopupMenuItem<String> _langItem(String code, String flag, String label) {
    return PopupMenuItem(
      value: code,
      child: Row(children: [
        Text(flag, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Text(label),
      ]),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _AnimatedPanel extends StatelessWidget {
  final Animation<Offset> slideAnim;
  final Animation<double> fadeAnim;
  final Widget child;

  const _AnimatedPanel({
    required this.slideAnim,
    required this.fadeAnim,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(
        position: slideAnim,
        child: child,
      ),
    );
  }
}


/// The trading day the cashier is about to sign into: the open Z, or the
/// business day a new Z would be opened on.
class _ZDayChip extends ConsumerWidget {
  const _ZDayChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final open = ref.watch(openZStreamProvider).valueOrNull;
    ref.watch(businessDayProvider);
    final text = open != null
        ? '${l10n.translate('z_current')}: ${ZService.displayName(open)}'
        : '${l10n.translate('no_open_z')} · ${l10n.translate('business_day')}: '
            '${ref.read(businessDayProvider.notifier).currentZDay()}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: open != null ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 16,
              color: open != null
                  ? cs.onPrimaryContainer
                  : cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: open != null
                    ? cs.onPrimaryContainer
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: cs.error.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: cs.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: cs.onErrorContainer,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;
  // `true` when the button sits over the colored brand gradient (white icons
  // on a dark tinted bg). `false` when it sits over the form panel's neutral
  // background — in that case use a surface-tinted bg with onSurface icons
  // so the white-on-white contrast bug doesn't bite in light themes.
  final bool onBrand;
  final String? tooltip;

  const _GlassButton({
    required this.onTap,
    required this.child,
    this.onBrand = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = onBrand
        ? Colors.black38
        : cs.surfaceContainerHighest.withValues(alpha: 0.85);
    final btn = Opacity(
      opacity: onTap != null ? 1.0 : 0.45,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: IconTheme(
              data: IconThemeData(
                color: onBrand ? Colors.white : cs.onSurface,
                size: 24,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}
