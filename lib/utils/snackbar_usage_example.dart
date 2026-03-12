/// Example usage of SnackBarHelper
///
/// This file demonstrates how to use the SnackBarHelper utility
/// to show conditional snack bars based on user settings.
///
/// IMPORTANT: Replace all direct ScaffoldMessenger.of(context).showSnackBar() calls
/// with SnackBarHelper methods to respect the global snack bar setting.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'snackbar_helper.dart';

// ==========================================
// OLD WAY (DO NOT USE)
// ==========================================

void showMessageOldWay(BuildContext context) {
  // ❌ This will always show, ignoring user preferences
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Message')),
  );
}

// ==========================================
// NEW WAY (USE THIS)
// ==========================================

void showMessageNewWay(BuildContext context, WidgetRef ref) {
  // ✅ This respects the user's snack bar setting
  SnackBarHelper.showSnackBar(context, ref, 'Message');
}

// ==========================================
// EXAMPLES
// ==========================================

class ExampleWidget extends ConsumerWidget {
  const ExampleWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // Example 1: Simple info message
        ElevatedButton(
          onPressed: () {
            SnackBarHelper.showInfoSnackBar(
              context,
              ref,
              'This is an informational message',
            );
          },
          child: const Text('Show Info'),
        ),

        // Example 2: Success message
        ElevatedButton(
          onPressed: () {
            SnackBarHelper.showSuccessSnackBar(
              context,
              ref,
              'Operation completed successfully!',
            );
          },
          child: const Text('Show Success'),
        ),

        // Example 3: Error message
        ElevatedButton(
          onPressed: () {
            SnackBarHelper.showErrorSnackBar(
              context,
              ref,
              'An error occurred. Please try again.',
            );
          },
          child: const Text('Show Error'),
        ),

        // Example 4: Warning message
        ElevatedButton(
          onPressed: () {
            SnackBarHelper.showWarningSnackBar(
              context,
              ref,
              'Warning: This action cannot be undone',
            );
          },
          child: const Text('Show Warning'),
        ),

        // Example 5: Custom duration
        ElevatedButton(
          onPressed: () {
            SnackBarHelper.showSnackBar(
              context,
              ref,
              'This message will stay for 5 seconds',
              duration: const Duration(seconds: 5),
            );
          },
          child: const Text('Show Long Message'),
        ),

        // Example 6: With action button
        ElevatedButton(
          onPressed: () {
            SnackBarHelper.showSnackBar(
              context,
              ref,
              'Item deleted',
              action: SnackBarAction(
                label: 'UNDO',
                onPressed: () {
                  // Handle undo action
                  print('Undo clicked');
                },
              ),
            );
          },
          child: const Text('Show with Action'),
        ),
      ],
    );
  }
}

// ==========================================
// MIGRATION GUIDE
// ==========================================

/// To migrate existing code:
///
/// 1. Find all instances of:
///    ScaffoldMessenger.of(context).showSnackBar(...)
///
/// 2. Replace with appropriate SnackBarHelper method:
///    - General messages: SnackBarHelper.showSnackBar(context, ref, message)
///    - Success messages: SnackBarHelper.showSuccessSnackBar(context, ref, message)
///    - Error messages: SnackBarHelper.showErrorSnackBar(context, ref, message)
///    - Info messages: SnackBarHelper.showInfoSnackBar(context, ref, message)
///    - Warning messages: SnackBarHelper.showWarningSnackBar(context, ref, message)
///
/// 3. Ensure your widget has access to WidgetRef:
///    - For StatelessWidget: extend ConsumerWidget instead
///    - For StatefulWidget: extend ConsumerStatefulWidget instead
///    - In build method: add WidgetRef ref parameter
///
/// Example migration:
///
/// BEFORE:
/// ```dart
/// class MyWidget extends StatelessWidget {
///   @override
///   Widget build(BuildContext context) {
///     return ElevatedButton(
///       onPressed: () {
///         ScaffoldMessenger.of(context).showSnackBar(
///           SnackBar(content: Text('Saved!')),
///         );
///       },
///       child: Text('Save'),
///     );
///   }
/// }
/// ```
///
/// AFTER:
/// ```dart
/// class MyWidget extends ConsumerWidget {
///   @override
///   Widget build(BuildContext context, WidgetRef ref) {
///     return ElevatedButton(
///       onPressed: () {
///         SnackBarHelper.showSuccessSnackBar(context, ref, 'Saved!');
///       },
///       child: Text('Save'),
///     );
///   }
/// }
/// ```

