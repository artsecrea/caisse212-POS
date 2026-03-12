import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';

/// Helper class for showing snack bars conditionally based on settings
class SnackBarHelper {
  /// Show a snack bar if enabled in settings
  static void showSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    Color? backgroundColor,
    bool isError = false,
  }) {
    final settings = ref.read(settingsProvider);

    // Only show if snack bars are enabled
    if (!settings.enableSnackBars) {
      return;
    }

    final snackBar = SnackBar(
      content: Text(message),
      duration: duration,
      action: action,
      backgroundColor: backgroundColor ??
        (isError ? Colors.red.shade700 : null),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// Show an error snack bar if enabled in settings
  static void showErrorSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    showSnackBar(
      context,
      ref,
      message,
      duration: duration,
      action: action,
      isError: true,
    );
  }

  /// Show a success snack bar if enabled in settings
  static void showSuccessSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final settings = ref.read(settingsProvider);

    if (!settings.enableSnackBars) {
      return;
    }

    final snackBar = SnackBar(
      content: Text(message),
      duration: duration,
      action: action,
      backgroundColor: Colors.green.shade700,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// Show an info snack bar if enabled in settings
  static void showInfoSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final settings = ref.read(settingsProvider);

    if (!settings.enableSnackBars) {
      return;
    }

    final snackBar = SnackBar(
      content: Text(message),
      duration: duration,
      action: action,
      backgroundColor: Colors.blue.shade700,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// Show a warning snack bar if enabled in settings
  static void showWarningSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    final settings = ref.read(settingsProvider);

    if (!settings.enableSnackBars) {
      return;
    }

    final snackBar = SnackBar(
      content: Text(message),
      duration: duration,
      action: action,
      backgroundColor: Colors.orange.shade700,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }
}

