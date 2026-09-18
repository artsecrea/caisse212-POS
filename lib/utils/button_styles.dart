import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Standardized button styles for the large-screen POS UI.
///
/// These build on the app theme (radius, control height) so bespoke buttons
/// match the global look. Prefer the semantic helpers ([primary], [success],
/// [danger], [tonal]) at call sites — they keep action buttons consistent and
/// legible across every page.
class AppButtonStyles {
  AppButtonStyles._();

  // Heights aligned with the theme's control height so inline buttons line up
  // with inputs and toolbar actions.
  static const double buttonHeight = AppTheme.controlHeight; // 52
  static const double largeButtonHeight = 60.0;

  static const EdgeInsets buttonPadding =
      EdgeInsets.symmetric(horizontal: 22, vertical: 14);
  static const EdgeInsets largeButtonPadding =
      EdgeInsets.symmetric(horizontal: 28, vertical: 18);

  static final BorderRadius _radius = BorderRadius.circular(AppTheme.radiusMd);

  // ── Semantic palette (works in light + dark) ───────────────────────────
  static const Color _successColor = Color(0xFF16A34A); // green-600
  static const Color _dangerColor = Color(0xFFDC2626); // red-600
  static const Color _warningColor = Color(0xFFD97706); // amber-600

  /// Primary call-to-action (filled with the brand color).
  static ButtonStyle primary({bool isLarge = false}) => _filled(
        AppTheme.seed,
        Colors.white,
        isLarge: isLarge,
      );

  /// Positive / confirming action (pay, save, confirm).
  static ButtonStyle success({bool isLarge = false}) =>
      _filled(_successColor, Colors.white, isLarge: isLarge);

  /// Destructive action (delete, cancel order, void).
  static ButtonStyle danger({bool isLarge = false}) =>
      _filled(_dangerColor, Colors.white, isLarge: isLarge);

  /// Cautionary action (hold, refund).
  static ButtonStyle warning({bool isLarge = false}) =>
      _filled(_warningColor, Colors.white, isLarge: isLarge);

  /// Low-emphasis filled button that adapts to the theme surface — use for
  /// secondary actions that should still read as a button.
  static ButtonStyle tonal(BuildContext context, {bool isLarge = false}) {
    final scheme = Theme.of(context).colorScheme;
    return _filled(scheme.secondaryContainer, scheme.onSecondaryContainer,
        isLarge: isLarge);
  }

  static ButtonStyle _filled(Color bg, Color fg, {bool isLarge = false}) {
    return ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: bg,
      foregroundColor: fg,
      disabledBackgroundColor: bg.withValues(alpha: 0.35),
      disabledForegroundColor: fg.withValues(alpha: 0.7),
      minimumSize: Size.fromHeight(isLarge ? largeButtonHeight : buttonHeight),
      padding: isLarge ? largeButtonPadding : buttonPadding,
      shape: RoundedRectangleBorder(borderRadius: _radius),
      textStyle: TextStyle(
        fontSize: isLarge ? 17 : 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ── Backward-compatible generic helpers (existing call sites) ───────────

  /// Elevated button style for large screens.
  static ButtonStyle elevatedButtonStyle({
    Color? backgroundColor,
    Color? foregroundColor,
    bool isLarge = false,
  }) {
    return ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      minimumSize: Size.fromHeight(isLarge ? largeButtonHeight : buttonHeight),
      padding: isLarge ? largeButtonPadding : buttonPadding,
      shape: RoundedRectangleBorder(borderRadius: _radius),
      textStyle: TextStyle(
        fontSize: isLarge ? 17 : 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Outlined button style for large screens.
  static ButtonStyle outlinedButtonStyle({
    Color? foregroundColor,
    Color? borderColor,
    bool isLarge = false,
  }) {
    return OutlinedButton.styleFrom(
      foregroundColor: foregroundColor,
      minimumSize: Size.fromHeight(isLarge ? largeButtonHeight : buttonHeight),
      padding: isLarge ? largeButtonPadding : buttonPadding,
      // No context here (static). A null `side` lets the app theme's
      // outlinedButtonTheme supply the border, which is theme-aware.
      side: borderColor == null
          ? null
          : BorderSide(color: borderColor, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: _radius),
      textStyle: TextStyle(
        fontSize: isLarge ? 17 : 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Text button style for large screens.
  static ButtonStyle textButtonStyle({
    Color? foregroundColor,
    bool isLarge = false,
  }) {
    return TextButton.styleFrom(
      foregroundColor: foregroundColor,
      minimumSize: Size.fromHeight(isLarge ? largeButtonHeight : buttonHeight),
      padding: isLarge ? largeButtonPadding : buttonPadding,
      shape: RoundedRectangleBorder(borderRadius: _radius),
      textStyle: TextStyle(
        fontSize: isLarge ? 17 : 15,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  /// Square icon button.
  static ButtonStyle iconButtonStyle({
    Color? backgroundColor,
    Color? foregroundColor,
    bool isLarge = false,
  }) {
    final size = isLarge ? largeButtonHeight : buttonHeight;
    return ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      minimumSize: Size(size, size),
      padding: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(borderRadius: _radius),
    );
  }
}
