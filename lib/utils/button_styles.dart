// filepath: /home/artecrea/StudioProjects/posecrea/lib/utils/button_styles.dart
import 'package:flutter/material.dart';

/// Standardized button styles for large touch screens
class AppButtonStyles {
  // Minimum height for buttons on large screens
  static const double buttonHeight = 56.0;
  static const double largeButtonHeight = 64.0;
  
  // Standard padding for buttons
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(horizontal: 24, vertical: 16);
  static const EdgeInsets largeButtonPadding = EdgeInsets.symmetric(horizontal: 32, vertical: 20);

  /// Elevated button style for large screens
  static ButtonStyle elevatedButtonStyle({
    Color? backgroundColor,
    Color? foregroundColor,
    bool isLarge = false,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      minimumSize: Size.fromHeight(isLarge ? largeButtonHeight : buttonHeight),
      padding: isLarge ? largeButtonPadding : buttonPadding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: TextStyle(
        fontSize: isLarge ? 18 : 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Outlined button style for large screens
  static ButtonStyle outlinedButtonStyle({
    Color? foregroundColor,
    Color? borderColor,
    bool isLarge = false,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: foregroundColor,
      minimumSize: Size.fromHeight(isLarge ? largeButtonHeight : buttonHeight),
      padding: isLarge ? largeButtonPadding : buttonPadding,
      side: BorderSide(color: borderColor ?? Colors.grey, width: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: TextStyle(
        fontSize: isLarge ? 18 : 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Text button style for large screens
  static ButtonStyle textButtonStyle({
    Color? foregroundColor,
    bool isLarge = false,
  }) {
    return TextButton.styleFrom(
      foregroundColor: foregroundColor,
      minimumSize: Size.fromHeight(isLarge ? largeButtonHeight : buttonHeight),
      padding: isLarge ? largeButtonPadding : buttonPadding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: TextStyle(
        fontSize: isLarge ? 18 : 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Icon button with larger size
  static ButtonStyle iconButtonStyle({
    Color? backgroundColor,
    Color? foregroundColor,
    bool isLarge = false,
  }) {
    return ElevatedButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      minimumSize: Size(isLarge ? largeButtonHeight : buttonHeight, isLarge ? largeButtonHeight : buttonHeight),
      padding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
