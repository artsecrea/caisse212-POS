import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart' show OnscreenKeyboardTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:window_manager/window_manager.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/update_provider.dart';
import '../widgets/caisse212_logo.dart';
import '../../services/api_service.dart';
import '../../services/data_sync_service.dart';
import '../../services/session_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/button_styles.dart';
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
  bool _isFullScreen = false;
  String? _errorMessage;
  List<User> _availableUsers = [];
  String? _selectedUsername;

  // Generate date-based password (YYYYMMDD format)
  String get _configPassword {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _checkFullScreenStatus();
  }

  Future<void> _loadUsers() async {
    try {
      final database = ref.read(databaseProvider);
      final users = await database.select(database.users).get();
      setState(() {
        _availableUsers = users;
      });
    } catch (e) {
      debugPrint('Error loading users: $e');
    }
  }

  /// Check current fullscreen status on startup
  Future<void> _checkFullScreenStatus() async {
    try {
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        final isFullScreen = await windowManager.isFullScreen();
        if (mounted) setState(() => _isFullScreen = isFullScreen);
      }
    } catch (_) {}
  }

  /// Toggle between fullscreen and windowed mode
  Future<void> _toggleFullScreen() async {
    try {
      final newState = !_isFullScreen;
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        await windowManager.setFullScreen(newState);
      } else if (Platform.isAndroid || Platform.isIOS) {
        if (newState) {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      }
      if (mounted) setState(() => _isFullScreen = newState);
    } catch (e) {
      debugPrint('Error toggling fullscreen: $e');
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _startingBalanceController.dispose();
    super.dispose();
  }

  /// Show server configuration dialog (protected by date password)
  Future<void> _showServerConfig() async {
    final passwordController = TextEditingController();

    // First, verify password
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('invalid_password_date')),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show server URL info
    final l10n = AppLocalizations.of(context)!;
    final prefs = ref.read(sharedPreferencesProvider);
    final serverUrl = prefs.getString('server_url') ?? l10n.translate('not_set');
    final demoMode = prefs.getBool('demo_mode') ?? false;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.translate('server_configuration')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.translate('current_configuration'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              _buildConfigRow('${l10n.translate('server_url')}:', serverUrl),
              const SizedBox(height: 8),
              _buildConfigRow('${l10n.translate('demo_mode')}:', demoMode ? l10n.translate('yes') : l10n.translate('no')),
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
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.translate('to_change_server_logout'),
                        style: TextStyle(color: Colors.blue[700], fontSize: 12),
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
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
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
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  /// Handle exit to tenant screen - requires tenant password verification
  Future<void> _handleExitToTenant() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final tenantPasswordHash = prefs.getString('tenant_password_hash');
    final l10n = AppLocalizations.of(context)!;

    if (tenantPasswordHash == null) {
      // No tenant password set, just go back
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
                  style: AppButtonStyles.textButtonStyle(isLarge: true),
                  child: Text(l10n.translate('cancel')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final password = passwordController.text.trim();
                    final verified = BCrypt.checkpw(password, tenantPasswordHash);
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
        // Unfocus all fields to dismiss on-screen keyboard before navigation.
        // Without this, AnimatedDefaultTextStyle dirty elements from the keyboard
        // try to rebuild in the wrong scope when the route is being deactivated.
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/tenant_login', (route) => false);
          }
        });
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

  /// Handle sync data from login screen
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

      // Show syncing message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('syncing_data')),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Perform sync
      await syncService.syncAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('sync_complete')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.translate('sync_error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Manual validation for fields using OnscreenKeyboardTextField
    if (_passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = AppLocalizations.of(context)!.translate('password_required');
      });
      return;
    }

    final l10n = AppLocalizations.of(context)!;

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

      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      // Try local authentication first
      final user = await (database.select(database.users)
            ..where((tbl) => tbl.username.equals(username)))
          .getSingleOrNull();

      if (user == null) {
        setState(() {
          _errorMessage = l10n.translate('user_not_found');
          _isLoading = false;
        });
        return;
      }

      final hash = user.password;
      final verified = BCrypt.checkpw(password, hash);

      // Also check custom password from SharedPreferences
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
        return;
      }

      if (user != null && (verified || customVerified)) {
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
                    content: Text(l10n.translate('resumed_session').replaceAll('{0}', existingSession.id.toString())),
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
                  content: Text(l10n.translate('started_new_session').replaceAll('{0}', newSession.id.toString())),
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
                content: Text(l10n.translate('session_error').replaceAll('{0}', e.toString())),
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

      // Clear current user and session
      ref.read(currentUserProvider.notifier).state = null;
      ref.read(currentSessionProvider.notifier).state = null;

      // Get API service and call logout endpoint
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);

      // Call logout API (this won't throw error, just logs if it fails)
      await apiService.logout();

      // Clear API service data INCLUDING tenant password hash
      await apiService.clearAllAuthData(); // Use clearAllAuthData for full logout

      // Dump/backup the database before clearing
      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);
      await syncService.dumpDatabaseBeforeClear();

      // Clear the database
      await syncService.clearAllData();

      if (mounted) {
        // Navigate to tenant login screen
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/tenant', (route) => false);
          }
        });
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
                            const Caisse212Logo(size: 80),
                            const SizedBox(height: 8),
                            Text(
                              l10n.translate('sign_in'),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            // User dropdown
                            DropdownButtonFormField<String>(
                              initialValue: _selectedUsername,
                              decoration: InputDecoration(
                                labelText: '${l10n.translate('username')} *',
                                prefixIcon: const Icon(Icons.person),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              isExpanded: true,
                              dropdownColor: Theme.of(context).colorScheme.surface,
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                              items: _availableUsers.map((user) {
                                final displayName =
                                    '${user.firstName} ${user.lastName}'.trim();
                                return DropdownMenuItem<String>(
                                  value: user.username,
                                  child: Row(
                                    children: [
                                      Icon(Icons.person, size: 20,
                                          color: Theme.of(context).colorScheme.onSurface),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          displayName.isNotEmpty
                                              ? displayName
                                              : user.username,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedUsername = value;
                                  _usernameController.text = value ?? '';
                                });
                              },
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return l10n.translate('username_required');
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            OnscreenKeyboardTextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                labelText: '${l10n.translate('password')} *',
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
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 20),
                            OnscreenKeyboardTextField(
                              controller: _startingBalanceController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: l10n.translate('starting_balance'),
                                prefixIcon: const Icon(Icons.account_balance_wallet),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                hintText: '0.0',
                              ),
                              style: const TextStyle(fontSize: 16),
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 20),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.red[300]!, width: 2),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.error_outline, color: Colors.red[700], size: 24),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(
                                          color: Colors.red[700],
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 32),
                            SizedBox(
                              height: 70,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
                                style: AppButtonStyles.elevatedButtonStyle(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                  isLarge: true,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.login, size: 28),
                                          const SizedBox(width: 12),
                                          Text(
                                            l10n.translate('sign_in'),
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
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
          // Exit button positioned at top-left - BIGGER
          Positioned(
            top: 20,
            left: 20,
            child: Material(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(16),
              elevation: 4,
              child: InkWell(
                onTap: _handleExitToTenant,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  child: const Icon(
                    Icons.exit_to_app,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // Report Issue button positioned at top-right - BIGGER
          Positioned(
            top: 20,
            right: 20,
            child: Row(
              children: [
                // Fullscreen toggle button
                Material(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 4,
                  child: InkWell(
                    onTap: _toggleFullScreen,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Sync button
                Material(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 4,
                  child: InkWell(
                    onTap: _isLoading ? null : _handleSync,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: const Icon(
                        Icons.sync,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Language selector button
                Material(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 4,
                  child: PopupMenuButton<String>(
                    onSelected: (languageCode) {
                      ref.read(settingsProvider.notifier).setLanguage(languageCode);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'en',
                        child: Row(
                          children: [
                            const Text('🇬🇧', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            const Text('English'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'fr',
                        child: Row(
                          children: [
                            const Text('🇫🇷', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            const Text('Français'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'ar',
                        child: Row(
                          children: [
                            const Text('🇲🇦', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 8),
                            const Text('العربية'),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: const Icon(
                        Icons.language,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Config button
                Material(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 4,
                  child: InkWell(
                    onTap: _showServerConfig,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: const Icon(
                        Icons.settings,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Report Issue button
                Material(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 4,
                  child: InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => const ReportIssueDialog(),
                      );
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: const Icon(
                        Icons.bug_report,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

