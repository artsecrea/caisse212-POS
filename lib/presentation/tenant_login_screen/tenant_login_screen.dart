import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart' show OnscreenKeyboardTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/utils/sample_data_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/database_providers.dart';
import '../../providers/update_provider.dart';
import '../widgets/report_issue_dialog.dart';
import '../widgets/update_dialog.dart';
import '../widgets/caisse212_logo.dart';

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
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
  }

  Future<void> _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('server_url') ?? 'https://app.caisse212';
    _serverUrlController.text = savedUrl;
    _posNameController.text = 'example';
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _posNameController.dispose();
    super.dispose();
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
        await showDialog<bool>(
          context: context,
          barrierDismissible: !isMandatory,
          builder: (context) => UpdateDialog(isMandatory: isMandatory),
        );

        // Note: We don't block navigation here, just inform the user
        // The login screen will also check and can enforce mandatory updates
      }
    } catch (e) {

      print('Error checking for updates: $e');
      // Don't block login flow if update check fails
    }
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

      // Check for updates after successful sync
      if (mounted) {
        await _checkForUpdates();
      }

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
      await apiService.setBusinessName('Demo Restaurant'); // Set default business name for demo

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

      // Check for updates (demo mode typically skips server calls, but we can still check)
      if (mounted) {
        await _checkForUpdates();
      }

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
                  const Text('Enter password:'),
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
            content: Text('Invalid password.'),
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
    if (_isLoadingData) {
      return _buildLoadingScreen(context);
    }

    final isWide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      body: Stack(
        children: [
          if (isWide)
            _buildWideLayout(context)
          else
            _buildCompactLayout(context),
          Positioned(
            top: 16,
            right: 16,
            child: _buildTopActions(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen(BuildContext context) {
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
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Caisse212Logo(size: 48),
                  const SizedBox(height: 24),
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

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withValues(alpha: 0.75),
                ],
              ),
            ),
            child: _buildBrandPanel(context),
          ),
        ),
        Expanded(
          flex: 6,
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 80),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _buildFormContent(context, showLogo: false),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(BuildContext context) {
    return Container(
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
          padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: _buildFormContent(context, showLogo: true),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandPanel(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(48, 80, 48, 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Caisse212Logo(size: 72),
            const SizedBox(height: 24),
            const Text(
              'CAISSE212',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Point of Sale System',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 48),
            Text(
              'First-time Setup',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),
            for (final item in <MapEntry<int, String>>[
              MapEntry(1, 'Connect to server'),
              MapEntry(2, 'Sign in as admin'),
              MapEntry(3, 'Set security password'),
              MapEntry(4, 'Sync all data'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${item.key}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      item.value,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormContent(BuildContext context, {required bool showLogo}) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLogo) ...[
            const Caisse212Logo(size: 56),
            const SizedBox(height: 16),
          ],
          Text(
            'Server Setup',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Connect to your server or use demo mode',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Server URL — hidden behind settings gear by default
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
                      if (!value.startsWith('http://') &&
                          !value.startsWith('https://')) {
                        return 'URL must start with http:// or https://';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => setState(() => _showServerUrl = false),
                  icon: const Icon(Icons.visibility_off),
                  tooltip: 'Hide Server URL',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    padding: const EdgeInsets.all(14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ] else ...[
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
                    iconSize: 28,
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],

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
          OnscreenKeyboardTextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password *',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
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
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red[300]!, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700], size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[700], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleServerLogin,
              icon: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_done, size: 24),
              label: Text(
                _isLoading ? 'Connecting...' : 'Connect to Server',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Divider(color: Colors.grey[400], thickness: 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'OR',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: Divider(color: Colors.grey[400], thickness: 1),
              ),
            ],
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _handleDemoMode,
              icon: const Icon(Icons.science, size: 22),
              label: const Text(
                'Use Demo Mode',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).primaryColor,
                side: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Center(
            child: TextButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const ReportIssueDialog(),
              ),
              icon: Icon(Icons.report_problem_outlined,
                  size: 18, color: Colors.grey[600]),
              label: Text(
                'Report Issue',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildOverlayIconButton(
          icon: Icons.bug_report_outlined,
          onTap: () => showDialog(
            context: context,
            builder: (_) => const ReportIssueDialog(),
          ),
        ),
      ],
    );
  }

  Widget _buildOverlayIconButton({
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.black38,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, size: 24, color: Colors.white),
        ),
      ),
    );
  }
}


