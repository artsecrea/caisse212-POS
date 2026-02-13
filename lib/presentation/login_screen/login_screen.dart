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
  String? _errorMessage;
  bool _showServerConfig = false;
  List<String> _availableUsernames = [];

  // Generate date-based password (YYYYMMDD format)
  String get _configPassword {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadUsernames();
  }

  /// Load available usernames from database
  Future<void> _loadUsernames() async {
    try {
      final database = ref.read(databaseProvider);
      final users = await database.select(database.users).get();
      setState(() {
        _availableUsernames = users.map((u) => u.username).toList();
      });
    } catch (e) {
      print('Error loading usernames: $e');
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
  Future<void> _showServerConfigDialog() async {
    final passwordController = TextEditingController();
    final l10n = AppLocalizations.of(context)!;

    // First, verify password
    final verified = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool obscurePassword = true;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Server Configuration'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter password:'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Password',
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
                  child: const Text('Verify'),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid password. Use today\'s date in YYYYMMDD format.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show server URL info
    final prefs = ref.read(sharedPreferencesProvider);
    final serverUrl = prefs.getString('server_url') ?? 'Not set';
    final demoMode = prefs.getBool('demo_mode') ?? false;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Server Configuration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Current Configuration:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              _buildConfigRow('Server URL:', serverUrl),
              const SizedBox(height: 8),
              _buildConfigRow('Demo Mode:', demoMode ? 'Yes' : 'No'),
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
                        'To change server settings, logout completely and reconnect from the tenant screen.',
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

      final username = _usernameController.text.trim();
      final password = _passwordController.text.trim();

      // Try local authentication first
      final user = await (database.select(database.users)
            ..where((tbl) => tbl.username.equals(username)))
          .getSingleOrNull();

      if (user == null) {
        setState(() {
          _errorMessage = 'User not found. Please check your username.';
          _isLoading = false;
        });
        return;
      }

      final hash = user.password;
      final verified = BCrypt.checkpw(password, hash);

      if (!verified) {
        setState(() {
          _errorMessage = 'Invalid password. Please try again.';
          _isLoading = false;
        });
        return;
      }

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
                            // Username autocomplete field
                            Autocomplete<String>(
                              initialValue: TextEditingValue(text: _usernameController.text),
                              optionsBuilder: (TextEditingValue textEditingValue) {
                                if (textEditingValue.text.isEmpty) {
                                  return _availableUsernames;
                                }
                                return _availableUsernames.where((String username) {
                                  return username.toLowerCase().contains(
                                    textEditingValue.text.toLowerCase(),
                                  );
                                });
                              },
                              onSelected: (String selection) {
                                _usernameController.text = selection;
                              },
                              fieldViewBuilder: (
                                BuildContext context,
                                TextEditingController fieldController,
                                FocusNode fieldFocusNode,
                                VoidCallback onFieldSubmitted,
                              ) {
                                // Sync with our main controller
                                fieldController.addListener(() {
                                  _usernameController.text = fieldController.text;
                                });

                                return TextFormField(
                                  controller: fieldController,
                                  focusNode: fieldFocusNode,
                                  decoration: InputDecoration(
                                    labelText: '${l10n.translate('username')} *',
                                    prefixIcon: const Icon(Icons.person),
                                    suffixIcon: _availableUsernames.isNotEmpty
                                        ? Icon(Icons.arrow_drop_down, color: Colors.grey[600])
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 16),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return l10n.translate('username_required');
                                    }
                                    if (value.trim().length < 3) {
                                      return 'Username must be at least 3 characters';
                                    }
                                    return null;
                                  },
                                  onFieldSubmitted: (value) => onFieldSubmitted(),
                                );
                              },
                              optionsViewBuilder: (
                                BuildContext context,
                                AutocompleteOnSelected<String> onSelected,
                                Iterable<String> options,
                              ) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 4.0,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      constraints: const BoxConstraints(maxHeight: 200),
                                      width: 380, // Match the field width approximately
                                      child: ListView.builder(
                                        padding: const EdgeInsets.all(8.0),
                                        itemCount: options.length,
                                        shrinkWrap: true,
                                        itemBuilder: (BuildContext context, int index) {
                                          final String option = options.elementAt(index);
                                          return InkWell(
                                            onTap: () {
                                              onSelected(option);
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16.0,
                                                vertical: 12.0,
                                              ),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.person, size: 20),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    option,
                                                    style: const TextStyle(fontSize: 16),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
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
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.translate('password_required');
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            TextFormField(
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
                              validator: (value) {
                                if (value != null && value.isNotEmpty) {
                                  final amount = double.tryParse(value);
                                  if (amount == null) {
                                    return 'Please enter a valid number';
                                  }
                                  if (amount < 0) {
                                    return 'Amount cannot be negative';
                                  }
                                }
                                return null;
                              },
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
                // Config button
                Material(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 4,
                  child: InkWell(
                    onTap: _showServerConfigDialog,
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

