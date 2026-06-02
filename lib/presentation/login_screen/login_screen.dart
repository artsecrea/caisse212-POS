import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart'
    show OnscreenKeyboardTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:window_manager/window_manager.dart';
import '../../data/database/app_database.dart';
import '../../providers/admin_elevation_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/user_provider.dart';
import '../../services/activity_log_service.dart';
import '../../utils/tenant_auth.dart';
import '../../providers/settings_provider.dart';
import '../../providers/update_provider.dart';
import '../widgets/caisse212_logo.dart';
import '../../services/api_service.dart';
import '../../services/data_sync_service.dart';
import '../../services/session_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/button_styles.dart';
import '../../utils/user_display.dart';
import '../main_screen/main_screen.dart';
import '../widgets/report_issue_dialog.dart';
import '../widgets/update_dialog.dart';


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
  late final List<Animation<double>> _featureFades;
  late final List<Animation<Offset>> _featureSlides;
  late final Animation<double> _shakeAnim;

  static const _features = [
    (Icons.speed_outlined, 'Fast order management'),
    (Icons.receipt_long_outlined, 'Thermal printing'),
    (Icons.wifi_off_outlined, 'Works fully offline'),
    (Icons.table_restaurant_outlined, 'Table management'),
  ];

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
    _checkFullScreenStatus();
    _entranceCtrl.forward();
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

    _featureFades = List.generate(
      _features.length,
      (i) => Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _entranceCtrl,
          curve: Interval(0.35 + i * 0.08, 0.70 + i * 0.06,
              curve: Curves.easeIn),
        ),
      ),
    );
    _featureSlides = List.generate(
      _features.length,
      (i) => Tween<Offset>(
        begin: const Offset(-0.18, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _entranceCtrl,
          curve: Interval(0.35 + i * 0.08, 0.75 + i * 0.06,
              curve: Curves.easeOutCubic),
        ),
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
      final database = ref.read(databaseProvider);
      final users = await database.select(database.users).get();
      setState(() => _availableUsers = users);
    } catch (e) {
      debugPrint('Error loading users: $e');
    }
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
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(l10n.translate('verify')),
                ),
              ],
            );
          },
        );
      },
    );
    passwordController.dispose();

    if (verified != true) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.translate('invalid_password_date')),
          backgroundColor: Colors.red,
        ));
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
      builder: (context) => AlertDialog(
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
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.translate('to_change_server_logout'),
                        style: TextStyle(
                            color: Colors.blue[700], fontSize: 12)),
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
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              isLarge: true,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.grey)),
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
    passwordController.dispose();

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.translate('invalid_tenant_password')),
          backgroundColor: Colors.red,
        ));
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
      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.translate('syncing_data')),
          duration: const Duration(seconds: 2),
        ));
      }
      await syncService.syncAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.translate('sync_complete')),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${l10n.translate('sync_error')}: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Login ──────────────────────────────────────────────────────────────────

  Future<void> _handleLogin() async {
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
      final database = ref.read(databaseProvider);
      final users = await database.select(database.users).get();
      if (users.isEmpty) {
        if (mounted) {
          await _performFullLogout(
              'Database is empty. Please reconnect to server or use demo mode.');
        }
        return;
      }

      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      final user = await (database.select(database.users)
            ..where((tbl) => tbl.username.equals(username)))
          .getSingleOrNull();

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

      bool customVerified = false;
      if (!verified) {
        final prefs = ref.read(sharedPreferencesProvider);
        final customHash = prefs.getString('custom_password_${user.id}');
        if (customHash != null) {
          try {
            customVerified = BCrypt.checkpw(password, customHash);
          } catch (_) {}
        }
      }

      if (!verified && !customVerified) {
        setState(() {
          _errorMessage = l10n.translate('invalid_password_try_again');
          _isLoading = false;
        });
        _shakeCtrl.forward(from: 0);
        return;
      }

      ref.read(currentUserProvider.notifier).state =
          CurrentUser.fromUser(user);
      // New session — never inherit a prior user's admin-mode elevation.
      ref.read(adminElevationProvider.notifier).state = null;

      // Record the login time so the users table shows an accurate last login.
      try {
        await ref.read(userRepositoryProvider).updateLastLogin(user.id);
      } catch (_) {}

      // Audit log uses the legal full name; the dropdown above and the
      // rest of the UI use displayLabel for friendliness.
      final actorName = '${user.firstName} ${user.lastName}'.trim();
      await ref.read(activityLogServiceProvider)
          .logLogin(userId: user.id, username: actorName);

      try {
        final sessionService = SessionService(database);
        final startingBalance =
            double.tryParse(_startingBalanceController.text) ?? 0.0;
        final existingSession =
            await sessionService.getActiveSession(user.id);

        if (existingSession != null) {
          if (existingSession.status == 'paused') {
            await sessionService.resumeSession(existingSession.id);
            final resumedSession =
                await sessionService.getSessionById(existingSession.id);
            ref.read(currentSessionProvider.notifier).state = resumedSession;
            await ref.read(activityLogServiceProvider)
                .logSessionResume(userId: user.id, username: actorName);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(l10n
                    .translate('resumed_session')
                    .replaceAll('{0}', existingSession.id.toString())),
                backgroundColor: Colors.green,
              ));
            }
          } else {
            ref.read(currentSessionProvider.notifier).state = existingSession;
          }
        } else {
          final newSession = await sessionService.startSession(
            cashierId: user.id,
            moneyAtStart: startingBalance,
          );
          ref.read(currentSessionProvider.notifier).state = newSession;
          await ref.read(activityLogServiceProvider)
              .logSessionStart(userId: user.id, username: actorName);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(l10n
                  .translate('started_new_session')
                  .replaceAll('{0}', newSession.id.toString())),
              backgroundColor: Colors.blue,
            ));
          }
        }
      } catch (e) {
        Logger.instance.error('Session error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n
                .translate('session_error')
                .replaceAll('{0}', e.toString())),
            backgroundColor: Colors.orange,
          ));
        }
      }

      if (mounted) {
        await _checkForUpdates();
        if (mounted) {
          Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainScreen()));
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Login failed: ${e.toString()}';
        _isLoading = false;
      });
      _shakeCtrl.forward(from: 0);
    }

    setState(() => _isLoading = false);
  }

  Future<void> _checkForUpdates() async {
    if (!Platform.isAndroid) return;
    try {
      final updateNotifier = ref.read(updateProvider.notifier);
      final hasUpdate = await updateNotifier.checkForUpdates();
      if (hasUpdate && mounted) {
        final updateState = ref.read(updateProvider);
        final isMandatory = updateState.updateRequired;
        final shouldProceed = await showDialog<bool>(
          context: context,
          barrierDismissible: !isMandatory,
          builder: (context) => UpdateDialog(isMandatory: isMandatory),
        );
        if (isMandatory && shouldProceed != true) {
          setState(() {
            _errorMessage = 'A mandatory update is required to continue.';
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      Logger.instance.warning('Update check failed (non-blocking): $e');
    }
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

      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);
      await apiService.logout();
      await apiService.clearAllAuthData();

      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Can\'t logout: please check your username and password'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isWide = MediaQuery.sizeOf(context).width >= 860;

    return Scaffold(
      body: isWide
          ? _buildWideLayout(context, l10n)
          : _buildCompactLayout(context, l10n),
    );
  }

  // ── Wide layout (desktop / landscape tablet) ───────────────────────────────

  Widget _buildWideLayout(BuildContext context, AppLocalizations l10n) {
    final primary = Theme.of(context).primaryColor;
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
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primary,
                        primary.withValues(alpha: 0.78),
                        primary.withValues(alpha: 0.55),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                  child: _buildBrandPanel(context),
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
        // Overlay buttons
        Positioned(
          top: 12,
          left: 12,
          child: _buildExitButton(onBrand: true),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: _buildActionBar(context),
        ),
      ],
    );
  }

  // ── Compact layout (mobile / portrait tablet) ──────────────────────────────

  Widget _buildCompactLayout(BuildContext context, AppLocalizations l10n) {
    final primary = Theme.of(context).primaryColor;

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
        Positioned(
            top: 12, left: 12, child: _buildExitButton(onBrand: true)),
        Positioned(
            top: 12, right: 12, child: _buildActionBar(context)),
      ],
    );
  }

  // ── Brand panel ─────────────────────────────────────────────────────────────

  Widget _buildBrandPanel(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 72, 40, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Animated logo
          FadeTransition(
            opacity: _logoFade,
            child: ScaleTransition(
              scale: _logoScale,
              child: const Caisse212Logo(size: 64),
            ),
          ),
          const SizedBox(height: 20),
          FadeTransition(
            opacity: _brandFade,
            child: SlideTransition(
              position: _brandSlide,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CAISSE212',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Point of Sale System',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 14,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 48),
          // Staggered feature list
          for (int i = 0; i < _features.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: FadeTransition(
                opacity: _featureFades[i],
                child: SlideTransition(
                  position: _featureSlides[i],
                  child: _FeatureItem(
                    icon: _features[i].$1,
                    label: _features[i].$2,
                  ),
                ),
              ),
            ),
          const Spacer(),
          FadeTransition(
            opacity: _brandFade,
            child: Text(
              '© 2025 Caisse212',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
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
                  child: const Caisse212Logo(size: 56),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            l10n.translate('sign_in'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

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
          OnscreenKeyboardTextField(
            controller: _startingBalanceController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.translate('starting_balance'),
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 18),
              hintText: '0.0',
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
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
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
        ],
      ),
    );
  }

  Widget _buildUserSelector(AppLocalizations l10n) {
    return DropdownButtonFormField<String>(
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
    return OnscreenKeyboardTextField(
      controller: _passwordController,
      obscureText: _obscurePassword,
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

  Widget _buildExitButton({bool onBrand = false}) {
    return _GlassButton(
      onTap: _handleExitToTenant,
      child: const Icon(Icons.exit_to_app, size: 24, color: Colors.white),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassButton(
          onTap: _isTogglingFullscreen ? null : _toggleFullScreen,
          child: Icon(
            _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
            size: 24,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        _GlassButton(
          onTap: _isLoading ? null : _handleSync,
          child: const Icon(Icons.sync, size: 24, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Material(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(12),
          child: PopupMenuButton<String>(
            onSelected: (code) =>
                ref.read(settingsProvider.notifier).setLanguage(code),
            itemBuilder: (_) => [
              _langItem('en', '🇬🇧', 'English'),
              _langItem('fr', '🇫🇷', 'Français'),
              _langItem('ar', '🇲🇦', 'العربية'),
            ],
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.language, size: 24, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _GlassButton(
          onTap: _showServerConfig,
          child: const Icon(Icons.settings, size: 24, color: Colors.white),
        ),
        const SizedBox(width: 6),
        _GlassButton(
          onTap: () => showDialog(
            context: context,
            builder: (_) => const ReportIssueDialog(),
          ),
          child:
              const Icon(Icons.bug_report, size: 24, color: Colors.white),
        ),
      ],
    );
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

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}


class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade300, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red.shade700,
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

  const _GlassButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap != null ? 1.0 : 0.45,
      child: Material(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(12),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: child,
          ),
        ),
      ),
    );
  }
}
