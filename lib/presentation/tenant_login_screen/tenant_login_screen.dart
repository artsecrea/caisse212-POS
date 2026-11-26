import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/database_providers.dart';
import '../../providers/update_provider.dart';
import '../widgets/report_issue_dialog.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/caisse212_logo.dart';
import '../super_admin/super_admin_tap_target.dart';
import '../../utils/pos_log.dart';
import '../widgets/adaptive_text_field.dart';
import '../../utils/snackbar_helper.dart';

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
    // Must end in `/api`: ApiService stores this as `api_base_url` and appends
    // a SECOND `/api` on every request, because the backend runs with servlet
    // context-path `/api` and its controllers are mapped at `/api/pos/...`.
    // A default without it produces `/api/pos/...`, which 404s as a static
    // resource. (It was also missing the `.com`, so it never resolved at all.)
    final savedUrl =
        prefs.getString('server_url') ?? 'https://app.caisse212.com/api';
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
      // Downloads silently; the login screen offers a mandatory one, the
      // global UpdateWatcher an optional one.
      await updateNotifier.checkForUpdates();
    } catch (e) {

      posLog('Error checking for updates: $e');
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
      // Trailing slashes stripped: the request path is appended directly, so a
      // pasted "…/api/" would produce "…/api//pos/orders".
      final serverUrl =
          _serverUrlController.text.trim().replaceAll(RegExp(r'/+$'), '');
      await prefs.setString('server_url', serverUrl);
      await prefs.setString('pos_name', _posNameController.text);
      await apiService.setBaseUrl(serverUrl);
      await apiService.setDemoMode(false);

      // Attempt login
      await apiService.login(
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

      final syncService = ref.read(dataSyncServiceFactoryProvider)(apiService);

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
      posLog(e);
      // `errorText` reads the status code and the server's own body off the
      // real exception. That beats matching substrings of a message that was
      // stringified two layers down — which is what this used to do, and why
      // it went blind the moment api_service stopped flattening DioException.
      var errorMsg = errorText(e, AppLocalizations.of(context)!);
      if (e is DioException &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.unknown)) {
        // Server-setup screen: the URL itself is the usual suspect here, so
        // keep the checklist that names it.
        errorMsg = 'Cannot connect to server. Please check:\n• Server URL is correct\n• Server is running\n• Network connection is active';
      }

      setState(() {
        _errorMessage = errorMsg;
        _isLoading = false;
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
                  AdaptiveKeyboardTextField(
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
                  AdaptiveKeyboardTextField(
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
                        color: AppTheme.tintFill(context, Colors.red),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.tintBorder(context, Colors.red)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppTheme.tintOn(context, Colors.red), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: TextStyle(color: AppTheme.tintOn(context, Colors.red), fontSize: 12),
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
      // Not disposed: the closing dialog still rebuilds its field with this controller for a few frames. It is collected with the dialog.
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
                  AdaptiveKeyboardTextField(
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
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: const Text('Verify'),
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
        SnackBarHelper.showToast('Invalid password.', kind: ToastKind.error);
      }
      return;
    }

    // Password verified - show server URL in the form
    setState(() {
      _showServerUrl = true;
    });

    if (mounted) {
      SnackBarHelper.showToast('Server URL unlocked. You can now edit it.', kind: ToastKind.success, duration: Duration(seconds: 2));
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
            // White sits on this, so it must stay dark in BOTH themes — a dark
            // scheme's `primary` is a pale blue. See [AppTheme.bar].
            colors: [
              AppTheme.bar(Theme.of(context).colorScheme),
              AppTheme.barAlt(Theme.of(context).colorScheme),
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
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
          // See [AppTheme.bar] — white content needs a dark ground in both
          // themes, and a dark scheme's `primary` is a pale blue.
          colors: [
            AppTheme.bar(Theme.of(context).colorScheme),
            AppTheme.barAlt(Theme.of(context).colorScheme),
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


  Widget _buildFormContent(BuildContext context, {required bool showLogo}) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showLogo) ...[
            const SuperAdminTapTarget(child: Caisse212Logo(size: 56)),
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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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

          AdaptiveKeyboardTextField(
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
          AdaptiveKeyboardTextField(
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
          AdaptiveKeyboardTextField(
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
                color: AppTheme.tintFill(context, Colors.red),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.tintBorder(context, Colors.red), width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: AppTheme.tintOn(context, Colors.red), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: AppTheme.tintOn(context, Colors.red), fontSize: 13),
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
                backgroundColor: const Color(0xFFF07041),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),

          const SizedBox(height: 20),

          const SizedBox(height: 16),

          Center(
            child: TextButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const ReportIssueDialog(),
              ),
              icon: Icon(Icons.report_problem_outlined,
                  size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
              label: Text(
                'Report Issue',
                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
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


