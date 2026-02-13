import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart' show OnscreenKeyboardTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:posecrea/services/api_service.dart';
import 'package:posecrea/services/data_sync_service.dart';
import 'package:posecrea/utils/sample_data_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/database_providers.dart';
import '../widgets/report_issue_dialog.dart';

class TenantLoginScreen extends ConsumerStatefulWidget {
  const TenantLoginScreen({super.key});

  @override
  ConsumerState<TenantLoginScreen> createState() => _TenantLoginScreenState();
}

class _TenantLoginScreenState extends ConsumerState<TenantLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _posNameController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingData = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String _loadingMessage = '';
  double _loadingProgress = 0.0;
  bool _showServerUrl = false; // Hide server URL by default

  // Generate date-based password (YYYYMMDD format)
  String get _serverSettingsPassword {
    final now = DateTime.now();
    print('${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}');
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_url') ?? 'http://localhost:8080';
    _serverUrlController.text = savedUrl;
    _posNameController.text = 'test';
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _posNameController.dispose();
    super.dispose();
  }

  Future<void> _handleServerLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiService = ApiService(prefs);

      // Save and set the base URL
      final serverUrl = _serverUrlController.text.trim();
      await prefs.setString('server_url', serverUrl);
      await prefs.setString('pos_name', _posNameController.text);
      await apiService.setBaseUrl(serverUrl);
      await apiService.setDemoMode(false);

      // Attempt login
      var data = await apiService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        posName: _posNameController.text.trim(),
      );

      print(data);

      // Login successful - ALWAYS prompt user to set a NEW tenant password
      // This ensures fresh security on each server connection
      setState(() => _isLoading = false);

      if (!mounted) return;

      final tenantPassword = await _showSetTenantPasswordDialog();

      if (tenantPassword == null || tenantPassword.isEmpty) {
        // User cancelled or didn't set password
        setState(() {
          _errorMessage = 'Tenant password is required to continue';
          _isLoading = false;
        });
        return;
      }

      // Hash and save the NEW tenant password (overwrites any old one)
      final passwordHash = BCrypt.hashpw(tenantPassword, BCrypt.gensalt());
      await prefs.setString('tenant_password_hash', passwordHash);

      // Login successful, now sync data
      setState(() {
        _isLoading = false;
        _isLoadingData = true;
        _loadingMessage = 'Syncing data...';
        _loadingProgress = 0.0;
      });

      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);

      syncService.onProgress = (message, progress) {
        if (mounted) {
          setState(() {
            _loadingMessage = message;
            _loadingProgress = progress;
          });
        }
      };

      await syncService.syncAllData();


      // Navigate to login screen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      print(e);
      String errorMsg = e.toString().replaceFirst('Exception: ', '');

      // Better error messages
      if (errorMsg.contains('Connection failed') || errorMsg.contains('Failed host lookup')) {
        errorMsg = 'Cannot connect to server. Please check:\n• Server URL is correct\n• Server is running\n• Network connection is active';
      } else if (errorMsg.contains('Network error')) {
        errorMsg = errorMsg.replaceFirst('Network error: ', '');
      } else if (errorMsg.contains('401') || errorMsg.contains('Unauthorized')) {
        errorMsg = 'Invalid credentials. Please check your username and password.';
      } else if (errorMsg.contains('404')) {
        errorMsg = 'Server endpoint not found. Please check the server URL.';
      } else if (errorMsg.contains('500')) {
        errorMsg = 'Server error. Please contact your administrator.';
      }

      setState(() {
        _errorMessage = errorMsg;
        _isLoading = false;
        _isLoadingData = false;
      });
    }
  }

  Future<void> _handleDemoMode() async {
    setState(() {
      _isLoadingData = true;
      _loadingMessage = 'Generating demo data...';
      _loadingProgress = 0.0;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiService = ApiService(prefs);

      // Set demo mode
      await apiService.setDemoMode(true);
      await apiService.setTenantId(0); // Demo tenant ID is 0
      await apiService.setPosName('DEMO-POS');

      final database = ref.read(databaseProvider);

      // Clear existing data
      setState(() {
        _loadingMessage = 'Clearing existing data...';
        _loadingProgress = 0.1;
      });

      final syncService = DataSyncService(database, apiService);
      await syncService.clearAllData();

      // Generate sample data
      setState(() {
        _loadingMessage = 'Generating sample data...';
        _loadingProgress = 0.5;
      });

      final generator = SampleDataGenerator(database);
      await generator.generateAll();

      setState(() {
        _loadingMessage = 'Demo setup complete!';
        _loadingProgress = 1.0;
      });

      // Navigate to login screen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Demo setup failed: ${e.toString()}';
        _isLoadingData = false;
      });
    }
  }

  /// Show dialog to set tenant password after successful server login
  Future<String?> _showSetTenantPasswordDialog() async {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscurePassword = true;
    bool obscureConfirmPassword = true;
    String? errorMessage;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Set Tenant Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Set a password to protect full logout and tenant access.\n\n'
                    'This password will be required to clear all data or change tenant settings.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  OnscreenKeyboardTextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Tenant Password',
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
                  const SizedBox(height: 16),
                  OnscreenKeyboardTextField(
                    controller: confirmPasswordController,
                    obscureText: obscureConfirmPassword,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            obscureConfirmPassword = !obscureConfirmPassword;
                          });
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (errorMessage != null) ...[
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
                          Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(color: Colors.red[700], fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    final password = passwordController.text.trim();
                    final confirmPassword = confirmPasswordController.text.trim();

                    if (password.isEmpty) {
                      setState(() {
                        errorMessage = 'Password is required';
                      });
                      return;
                    }

                    if (password.length < 4) {
                      setState(() {
                        errorMessage = 'Password must be at least 4 characters';
                      });
                      return;
                    }

                    if (password != confirmPassword) {
                      setState(() {
                        errorMessage = 'Passwords do not match';
                      });
                      return;
                    }

                    Navigator.of(context).pop(password);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  child: const Text('Set Password', style: TextStyle(fontSize: 16)),
                ),
              ],
            );
          },
        );
      },
    ).then((value) {
      passwordController.dispose();
      confirmPasswordController.dispose();
      return value;
    });
  }

  /// Show server settings dialog with password protection
  Future<void> _showServerSettingsDialog() async {
    final passwordController = TextEditingController();

    // First, verify password
    final verified = await showDialog<bool>(
      context: context,
      builder: (context) {
        bool obscurePassword = true;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Server Settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Enter today\'s date as password (YYYYMMDD):'),
                  const SizedBox(height: 16),
                  OnscreenKeyboardTextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.admin_panel_settings),
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
                      hintText: 'Example: 20250213',
                    ),
                    autofocus: true,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final password = passwordController.text.trim();
                    Navigator.of(context).pop(password == _serverSettingsPassword);
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

    // Password verified - show server URL in the form
    setState(() {
      _showServerUrl = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Server URL unlocked. You can now edit it.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen during data sync
    if (_isLoadingData) {
      return Scaffold(
      body: Container(
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
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    Text(
                      _loadingMessage,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _loadingProgress,
                      backgroundColor: Colors.grey[300],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(_loadingProgress * 100).toInt()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
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
                  constraints: const BoxConstraints(maxWidth: 500),
                  padding: const EdgeInsets.all(40.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.cloud_sync,
                          size: 80,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'POS System Setup',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Connect to your server or use demo mode',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Server URL (hidden behind config icon)
                        if (_showServerUrl) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _serverUrlController,
                                  decoration: InputDecoration(
                                    labelText: 'Server URL',
                                    prefixIcon: const Icon(Icons.dns),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  style: const TextStyle(fontSize: 14),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Server URL is required';
                                    }
                                    if (!value.startsWith('http://') && !value.startsWith('https://')) {
                                      return 'URL must start with http:// or https://';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _showServerUrl = false;
                                  });
                                },
                                icon: const Icon(Icons.visibility_off),
                                tooltip: 'Hide Server URL',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.grey[200],
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ] else ...[
                          // Config icon to reveal server URL
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: IconButton(
                                  onPressed: _showServerSettingsDialog,
                                  icon: const Icon(Icons.settings),
                                  tooltip: 'Configure Server (Protected)',
                                  iconSize: 32,
                                  style: IconButton.styleFrom(
                                    padding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],

                        // POS Name
                        OnscreenKeyboardTextField(
                          controller: _posNameController,
                          decoration: InputDecoration(
                            labelText: 'POS Name *',
                            prefixIcon: const Icon(Icons.point_of_sale),

                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 20),

                        // Username
                        OnscreenKeyboardTextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Username *',
                            prefixIcon: const Icon(Icons.person),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 20),

                        // Password
                        OnscreenKeyboardTextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password *',
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

                        const SizedBox(height: 32),

                        // Connect to Server button - BIGGER
                        SizedBox(
                          height: 60,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _handleServerLogin,
                            icon: _isLoading
                                ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                                : const Icon(Icons.cloud_done, size: 28),
                            label: Text(
                              _isLoading ? 'Connecting...' : 'Connect to Server',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 4,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Divider with "OR"
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey[400], thickness: 1.5)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey[400], thickness: 1.5)),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Demo Mode button - BIGGER
                        SizedBox(
                          height: 60,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _handleDemoMode,
                            icon: const Icon(Icons.science, size: 28),
                            label: const Text(
                              'Use Demo Mode',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).primaryColor,
                              side: BorderSide(
                                color: Theme.of(context).primaryColor,
                                width: 2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // API Tester button
                        SizedBox(
                          height: 50,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pushNamed('/api-tester');
                            },
                            icon: const Icon(Icons.bug_report, size: 24),
                            label: const Text(
                              'Test API Endpoints',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange[700],
                              side: BorderSide(
                                color: Colors.orange[700]!,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Report Issue button
                        SizedBox(
                          height: 50,
                          child: TextButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => const ReportIssueDialog(),
                              );
                            },
                            icon: const Icon(Icons.report_problem, size: 24),
                            label: const Text(
                              'Report Issue',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[700],
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
    );
  }
}


