import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart' show OnscreenKeyboardTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../providers/stat_provider.dart';
import '../../services/session_service.dart';
import '../../services/api_service.dart';
import '../../services/data_sync_service.dart';
import '../../providers/database_providers.dart';
import '../main_screen/main_screen.dart';
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _startingBalanceController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
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
      // Check internet connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = connectivityResult != ConnectivityResult.none;

      // Check if database is empty (first time login)
      final database = ref.read(databaseProvider);
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

      // Try local authentication first
      final user = await (database.select(database.users)
            ..where((tbl) =>
                tbl.username.equals(_usernameController.text) &
                tbl.password.equals(_passwordController.text)))
          .getSingleOrNull();

      if (user != null) {
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
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainScreen()),
          );
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

      // Clear API service data
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);
      await apiService.clearAuthData();

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
            content: Text('Error during logout: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final time = ref.watch(timeProvider).value ?? DateTime.now();
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.7),
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
                      Text(
                        _formatTime(time),
                        style: const TextStyle(fontSize: 24),
                      ),
                        const SizedBox(height: 16),
                        Text(
                          'POS System',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to continue',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        OnscreenKeyboardTextField(

                          controller: _usernameController,
                          decoration: InputDecoration(

                            labelText: 'Username',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
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
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        OnscreenKeyboardTextField(
                          controller: _startingBalanceController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Starting Balance',
                            prefixIcon: const Icon(Icons.account_balance_wallet),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          )
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
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(fontSize: 16),
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
    );
  }
}

