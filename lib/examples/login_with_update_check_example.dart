// Example: How to integrate update check in your login flow

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/update_provider.dart';
import '../presentation/widgets/update_dialog.dart';

/// Add this method to your login screen state class
class _LoginScreenState extends ConsumerState<LoginScreen> {

  // ... existing code ...

  /// Check for updates after successful login
  Future<void> _checkForUpdatesAfterLogin(BuildContext context) async {
    // Trigger update check
    await ref.read(updateProvider.notifier).checkForUpdates();

    // Get current update state
    final updateState = ref.read(updateProvider);

    // If update is available
    if (updateState.availableUpdate != null && mounted) {
      // Show update dialog
      await showDialog(
        context: context,
        barrierDismissible: !updateState.updateRequired,
        builder: (context) => UpdateDialog(
          isMandatory: updateState.updateRequired,
        ),
      );

      // If update is mandatory, don't proceed to main screen
      if (updateState.updateRequired) {
        // User must update to continue
        return;
      }
    }

    // Navigate to main screen if no mandatory update
    if (mounted && !ref.read(updateProvider).updateRequired) {
      Navigator.pushReplacementNamed(context, '/main');
    }
  }

  /// Your existing login method - modify to call update check
  Future<void> _handleLogin() async {
    // ... your existing login logic ...

    final success = await _performLogin(); // Your login method

    if (success && mounted) {
      // Check for updates after successful login
      await _checkForUpdatesAfterLogin(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ... your existing login UI ...

    return Scaffold(
      body: Column(
        children: [
          // ... your login form ...

          ElevatedButton(
            onPressed: _handleLogin,
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }
}
