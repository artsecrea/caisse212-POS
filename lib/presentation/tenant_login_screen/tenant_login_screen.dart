import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart' show OnscreenKeyboardTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posecrea/services/api_service.dart';
import 'package:posecrea/services/data_sync_service.dart';
import 'package:posecrea/utils/sample_data_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/database_providers.dart';

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

  @override
  void initState() {
    super.initState();
    // Set default server URL - can be changed
    _serverUrlController.text = 'https://api.yourserver.com';
    _posNameController.text = 'POS-1';
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

      // Set the base URL
      await apiService.setBaseUrl(_serverUrlController.text.trim());
      await apiService.setDemoMode(false);

      // Attempt login
      var data = await apiService.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        posName: _posNameController.text.trim(),
      );

      // Save tenant password hash before clearing
      final tenantPasswordHash = prefs.getString('tenant_password_hash');

      print(data);

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

      // Restore tenant password hash if it was saved
      if (tenantPasswordHash != null) {
        await prefs.setString('tenant_password_hash', tenantPasswordHash);
      }

      // Navigate to login screen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      print(e);
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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

                        // Server URL
                        OnscreenKeyboardTextField(
                          controller: _serverUrlController,
                          decoration: InputDecoration(
                            labelText: 'Server URL',
                            prefixIcon: const Icon(Icons.dns),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // POS Name
                        OnscreenKeyboardTextField(
                          controller: _posNameController,
                          decoration: InputDecoration(
                            labelText: 'POS Name',
                            prefixIcon: const Icon(Icons.point_of_sale),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),

                        ),
                        const SizedBox(height: 16),

                        // Username
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

                        // Password
                        OnscreenKeyboardTextField(
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

                        // Connect to Server button
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _handleServerLogin,
                          icon: _isLoading
                              ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                              : const Icon(Icons.cloud_done),
                          label: Text(
                            _isLoading ? 'Connecting...' : 'Connect to Server',
                            style: const TextStyle(fontSize: 16),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Divider with "OR"
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey[400])),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey[400])),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Demo Mode button
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleDemoMode,
                          icon: const Icon(Icons.science),
                          label: const Text(
                            'Use Demo Mode',
                            style: TextStyle(fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // API Tester button
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pushNamed('/api-tester');
                          },
                          icon: const Icon(Icons.bug_report),
                          label: const Text(
                            'Test API Endpoints',
                            style: TextStyle(fontSize: 16),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: Colors.orange[700]!),
                            foregroundColor: Colors.orange[700],
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