import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import 'app_localizations.dart';
import 'error_text.dart';

/// SnackBar helper.
///
/// Two APIs, by design:
///
/// 1. **`error/success/info/warning(context, message)`** — takes only a
///    [BuildContext]. Always shows, regardless of the
///    `settings.enableSnackBars` toggle. Uses [ColorScheme] tokens so dark
///    mode behaves correctly. Use this for migrating raw
///    `ScaffoldMessenger.of(context).showSnackBar(...)` calls.
///
/// 2. **`showSnackBar/showXxxSnackBar(context, ref, message)`** — original
///    settings-gated API. Kept for backward compatibility with the call
///    sites that already use it; internally now uses [ColorScheme] tokens
///    instead of hardcoded `Colors.X.shade700`. Use for routine
///    notifications a user might want to silence (sync started, item
///    queued, etc.). Errors via this API still honor the toggle — if you
///    need a "must show" error, use `error(context, ...)` instead.
class SnackBarHelper {
  // ── New ref-free API ───────────────────────────────────────────────────────

  /// Show an error. Always visible, regardless of settings. Uses
  /// `colorScheme.error` so it adapts to dark mode.
  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    _show(context, message,
        duration: duration,
        action: action,
        kind: _SnackKind.error);
  }

  /// Show a success. Always visible, regardless of settings.
  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _show(context, message,
        duration: duration,
        action: action,
        kind: _SnackKind.success);
  }

  /// Show an info message. Always visible, regardless of settings.
  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _show(context, message,
        duration: duration,
        action: action,
        kind: _SnackKind.info);
  }

  /// Show a warning. Always visible, regardless of settings.
  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    _show(context, message,
        duration: duration,
        action: action,
        kind: _SnackKind.warning);
  }

  // ── Original settings-gated API (kept for backward compat) ─────────────────

  /// Show a snack bar if enabled in settings.
  static void showSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    Color? backgroundColor,
    bool isError = false,
  }) {
    if (!ref.read(settingsProvider).enableSnackBars) return;

    if (backgroundColor != null) {
      // Caller explicitly passed a color — honor it (legacy path).
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        duration: duration,
        action: action,
        backgroundColor: backgroundColor,
      ));
      return;
    }
    _show(context, message,
        duration: duration,
        action: action,
        kind: isError ? _SnackKind.error : _SnackKind.neutral);
  }

  /// Show an error snack bar.
  ///
  /// **Not** gated on `enableSnackBars`, despite taking a [ref] — the toggle
  /// exists to silence routine chatter (sync started, item queued), and it
  /// defaults to off. Honouring it here meant that on a default install every
  /// failure in the app was invisible: a payment that did not save, a sync that
  /// did not run, a booking the server refused, all silently swallowed while
  /// the cashier believed the tap had worked. A failure the user is never told
  /// about is worse than a noisy one.
  ///
  /// [ref] is kept so the ~30 existing call sites need no edit.
  static void showErrorSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    _show(context, message,
        duration: duration, action: action, kind: _SnackKind.error);
  }

  /// Show a thrown [error], translated into something a cashier can act on.
  ///
  /// Prefer this to `error(context, '$e')` anywhere an exception is caught:
  /// it strips the Dart framing, maps transport failures to "check the
  /// connection" in the app's language, and lets a message the server actually
  /// wrote through untouched. See [errorText].
  static void failure(
    BuildContext context,
    Object? error, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    final l10n = AppLocalizations.of(context);
    _show(
      context,
      l10n == null ? '$error' : errorText(error, l10n),
      duration: duration,
      action: action,
      kind: _SnackKind.error,
    );
  }

  /// Show a success snack bar if enabled in settings.
  static void showSuccessSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!ref.read(settingsProvider).enableSnackBars) return;
    _show(context, message,
        duration: duration, action: action, kind: _SnackKind.success);
  }

  /// Show an info snack bar if enabled in settings.
  static void showInfoSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!ref.read(settingsProvider).enableSnackBars) return;
    _show(context, message,
        duration: duration, action: action, kind: _SnackKind.info);
  }

  /// Show a warning snack bar if enabled in settings.
  static void showWarningSnackBar(
    BuildContext context,
    WidgetRef ref,
    String message, {
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) {
    if (!ref.read(settingsProvider).enableSnackBars) return;
    _show(context, message,
        duration: duration, action: action, kind: _SnackKind.warning);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static void _show(
    BuildContext context,
    String message, {
    required Duration duration,
    required SnackBarAction? action,
    required _SnackKind kind,
  }) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (kind) {
      _SnackKind.error => (cs.error, cs.onError),
      _SnackKind.success => (cs.tertiary, cs.onTertiary),
      _SnackKind.warning => (cs.tertiaryContainer, cs.onTertiaryContainer),
      _SnackKind.info => (cs.secondary, cs.onSecondary),
      _SnackKind.neutral => (cs.inverseSurface, cs.onInverseSurface),
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: TextStyle(color: fg)),
      duration: duration,
      action: action,
      backgroundColor: bg,
    ));
  }
}

enum _SnackKind { error, success, info, warning, neutral }
