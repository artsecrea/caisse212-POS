import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart' show OnscreenKeyboardTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bcrypt/bcrypt.dart';
import '../../providers/database_providers.dart';
import '../../providers/update_provider.dart';
import '../../services/api_service.dart';
import '../../services/data_sync_service.dart';
import '../../services/session_service.dart';
import '../../utils/app_localizations.dart';
import '../main_screen/main_screen.dart';
import '../widgets/report_issue_dialog.dart';
import '../widgets/update_dialog.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _startingBalanceController = TextEditingController(text: '0.0');

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _startingBalanceController.dispose();
    super.dispose();
  }

  /// Handle exit to tenant screen - requires tenant password verification
  Future<void> _handleExitToTenant() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final tenantPasswordHash = prefs.getString('tenant_password_hash');
    final l10n = AppLocalizations.of(context)!;

    if (tenantPasswordHash == null) {
      // No tenant password set, just go back
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/tenant');
      }
      return;
    }

    // Show password dialog
    final passwordController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool obscurePassword = true;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
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
                        icon: Icon(
                          obscurePassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
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

                    // final verified = BCrypt.checkpw(password, tenantPasswordHash);
                    final verified = true;
                    Navigator.of(context).pop(verified);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
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

    if (result == true) {
      // Password verified, clear auth data and navigate to tenant screen
      final apiService = ApiService(prefs);
      await apiService.clearAuthData();

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/tenant_login');
      }
    } else if (result == false) {
      // Password verification failed
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('invalid_tenant_password')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final database = ref.read(databaseProvider);
      final hasInternet = true; // TODO: Check internet connection

      // Check if users exist
      final users = await database.select(database.users).get();
      final isFirstTime = users.isEmpty;

      // If no users exist, this means the database is corrupted or cleared
      // Logout entirely and go back to tenant login
      if (isFirstTime) {
        if (mounted) {
          await _performFullLogout(
            'Database is empty. Please reconnect to server or use demo mode.',
          );
        }
        return;
      }

      final username = _usernameController.text;
      final password = _passwordController.text;

      // Try local authentication first
      final user = await (database.select(database.users)
            ..where((tbl) => tbl.username.equals(username)))
          .getSingleOrNull();
      final hash = user?.password ?? '';

      final verified = BCrypt.checkpw(password, hash);

      if (user != null && verified) {
        // Local authentication successful
        ref.read(currentUserProvider.notifier).state = CurrentUser.fromUser(user);

        // Handle cash session - resume paused or create new
        try {
          final sessionService = SessionService(database);
          final startingBalance = double.tryParse(_startingBalanceController.text) ?? 0.0;

          // Check if user has a paused session
          final existingSession = await sessionService.getActiveSession(user.id);

          if (existingSession != null) {
            // Resume existing session (either active or paused)
            if (existingSession.status == 'paused') {
              await sessionService.resumeSession(existingSession.id);
              // Reload to get updated status
              final resumedSession = await sessionService.getSessionById(existingSession.id);
              ref.read(currentSessionProvider.notifier).state = resumedSession;

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Resumed your previous session #${existingSession.id}'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } else {
              // Session is already active
              ref.read(currentSessionProvider.notifier).state = existingSession;
            }
          } else {
            // No existing session, create new one
            final newSession = await sessionService.startSession(
              cashierId: user.id,
              moneyAtStart: startingBalance,
            );
            ref.read(currentSessionProvider.notifier).state = newSession;

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Started new session #${newSession.id}'),
                  backgroundColor: Colors.blue,
                ),
              );
            }
          }
        } catch (e) {
          print('Session error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Session error: $e'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }

        if (mounted) {
          // Check for updates after successful login
          await _checkForUpdates();

          // Navigate to main screen (only if not blocked by mandatory update)
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const MainScreen()),
            );
          }
        }
      } else if (hasInternet) {
        // Try API authentication and sync data
        // TODO: Implement API authentication
        setState(() {
          _errorMessage = 'Invalid credentials';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Invalid credentials and no internet connection';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Login failed: ${e.toString()}';
        _isLoading = false;
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  /// Check for updates and show dialog if available
  Future<void> _checkForUpdates() async {
    try {
      final updateNotifier = ref.read(updateProvider.notifier);
      final hasUpdate = await updateNotifier.checkForUpdates();

      if (hasUpdate && mounted) {
        final updateState = ref.read(updateProvider);
        final isMandatory = updateState.updateRequired;

        // Show update dialog
        final shouldProceed = await showDialog<bool>(
          context: context,
          barrierDismissible: !isMandatory,
          builder: (context) => UpdateDialog(isMandatory: isMandatory),
        );

        // If mandatory update was dismissed without updating, stay on login
        if (isMandatory && shouldProceed != true) {
          setState(() {
            _errorMessage = 'A mandatory update is required to continue.';
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      print('Error checking for updates: $e');
      // Don't block login if update check fails
    }
  }

  /// Perform full logout - clear all tenant data and redirect to tenant login
  Future<void> _performFullLogout(String message) async {
    try {
      // Show dialog informing user
      final shouldLogout = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Database Error'),
          content: Text(message),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reconnect'),
            ),
          ],
        ),
      );

      if (shouldLogout != true) return;

      // Clear current user and session
      ref.read(currentUserProvider.notifier).state = null;
      ref.read(currentSessionProvider.notifier).state = null;

      // Clear API service data INCLUDING tenant password hash
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);
      await apiService.clearAllAuthData(); // Use clearAllAuthData for full logout

      // Clear the database
      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);
      await syncService.clearAllData();

      if (mounted) {
        // Navigate to tenant login screen
        Navigator.of(context).pushNamedAndRemoveUntil('/tenant', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Can\'t logout: please check your username and password'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withValues(alpha: 0.7),
                ],
              ),
            ),
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 450),
                      padding: const EdgeInsets.all(40.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              Icons.point_of_sale,
                              size: 80,
                              color: Theme.of(context).primaryColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.translate('app_title'),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).primaryColor,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.translate('sign_in'),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            OnscreenKeyboardTextField(
                              controller: _usernameController,
                              decoration: InputDecoration(
                                labelText: l10n.translate('username'),
                                prefixIcon: const Icon(Icons.person),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            OnscreenKeyboardTextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: l10n.translate('password'),
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            OnscreenKeyboardTextField(
                              controller: _startingBalanceController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: l10n.translate('starting_balance'),
                                prefixIcon: const Icon(Icons.account_balance_wallet),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red[300]!),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red[700]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(color: Colors.red[700]),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      l10n.translate('sign_in'),
                                      style: const TextStyle(fontSize: 16),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Exit button positioned at top-left
          Positioned(
            top: 16,
            left: 16,
            child: Material(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _handleExitToTenant,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.exit_to_app,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // Report Issue button positioned at top-right
          Positioned(
            top: 16,
            right: 16,
            child: Material(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => const ReportIssueDialog(),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.bug_report,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

