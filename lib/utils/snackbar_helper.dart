import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
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
        kind: ToastKind.error);
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
        kind: ToastKind.success);
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
        kind: ToastKind.info);
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
        kind: ToastKind.warning);
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

    _show(context, message,
        duration: duration,
        action: action,
        kind: isError ? ToastKind.error : ToastKind.neutral);
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
        duration: duration, action: action, kind: ToastKind.error);
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
      kind: ToastKind.error,
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
        duration: duration, action: action, kind: ToastKind.success);
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
        duration: duration, action: action, kind: ToastKind.info);
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
        duration: duration, action: action, kind: ToastKind.warning);
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  static void _show(
    BuildContext context,
    String message, {
    required Duration duration,
    required SnackBarAction? action,
    required ToastKind kind,
  }) {
    showToast(message, kind: kind, duration: duration, action: action);
  }

  // ── Toasts ─────────────────────────────────────────────────────────────────

  static final ValueNotifier<List<_ToastEntry>> _toasts =
      ValueNotifier(const []);
  static int _nextToastId = 0;
  static final Map<int, Timer> _toastTimers = {};

  /// More than this and the oldest goes: a burst of sync errors should not
  /// wall off the right edge of the till.
  static const int _maxToasts = 4;

  /// Show a toast in the top-right corner, under the top bar.
  ///
  /// Deliberately needs no [BuildContext]: plenty of call sites show a
  /// message after an `await`, when their own context may already be gone.
  /// Toasts are drawn by [ToastHost], which sits in the app's root builder
  /// above every route and dialog, so a toast raised from inside a dialog is
  /// still visible, and survives the dialog closing.
  static void showToast(
    String message, {
    ToastKind kind = ToastKind.info,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
    String? title,
  }) {
    final entry = _ToastEntry(
      id: _nextToastId++,
      message: message,
      title: title,
      kind: kind,
      action: action,
    );
    var list = [..._toasts.value, entry];
    while (list.length > _maxToasts) {
      _toastTimers.remove(list.first.id)?.cancel();
      list = list.sublist(1);
    }
    _toasts.value = list;
    _toastTimers[entry.id] = Timer(duration, () => dismissToast(entry.id));
  }

  static void dismissToast(int id) {
    _toastTimers.remove(id)?.cancel();
    _toasts.value = [
      for (final t in _toasts.value)
        if (t.id != id) t,
    ];
  }

  static void dismissAllToasts() {
    for (final t in _toastTimers.values) {
      t.cancel();
    }
    _toastTimers.clear();
    _toasts.value = const [];
  }
}

/// What a toast is about — picks its accent colour and icon.
enum ToastKind { error, success, info, warning, neutral }

class _ToastEntry {
  _ToastEntry({
    required this.id,
    required this.message,
    required this.kind,
    this.title,
    this.action,
  });

  final int id;
  final String message;
  final String? title;
  final ToastKind kind;
  final SnackBarAction? action;
}

/// Draws the toasts raised through [SnackBarHelper]. Mounted once, in the
/// MaterialApp builder, stacked over the app.
class ToastHost extends StatelessWidget {
  const ToastHost({super.key});

  /// Clears the top bar, so the toasts do not sit on the buttons in it.
  static const double _top = 64;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<_ToastEntry>>(
      valueListenable: SnackBarHelper._toasts,
      builder: (context, toasts, _) {
        if (toasts.isEmpty) return const SizedBox.shrink();
        final screenWidth = MediaQuery.sizeOf(context).width;
        final width = (screenWidth - 32).clamp(200.0, 380.0);
        return Positioned(
          top: _top + MediaQuery.paddingOf(context).top,
          right: 16,
          width: width,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Newest on top, where the eye already is.
                for (final t in toasts.reversed)
                  Padding(
                    key: ValueKey(t.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SlideIn(child: _Toast(entry: t)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SlideIn extends StatefulWidget {
  const _SlideIn({required this.child});

  final Widget child;

  @override
  State<_SlideIn> createState() => _SlideInState();
}

class _SlideInState extends State<_SlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0.25, 0), end: Offset.zero)
            .animate(curve),
        child: widget.child,
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.entry});

  final _ToastEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final (MaterialColor? hue, IconData icon) = switch (entry.kind) {
      ToastKind.error => (Colors.red, Icons.error_outline),
      ToastKind.success => (Colors.green, Icons.check_circle_outline),
      ToastKind.warning => (Colors.orange, Icons.warning_amber_rounded),
      ToastKind.info => (null, Icons.info_outline),
      ToastKind.neutral => (null, Icons.notifications_none),
    };
    final accent = hue == null
        ? (entry.kind == ToastKind.info ? cs.primary : cs.onSurfaceVariant)
        : (dark ? hue.shade300 : hue.shade700);
    final title = entry.title;
    final action = entry.action;

    return Dismissible(
      key: ValueKey('toast-${entry.id}'),
      direction: DismissDirection.startToEnd,
      onDismissed: (_) => SnackBarHelper.dismissToast(entry.id),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? cs.surfaceContainerHighest : cs.surface,
          borderRadius: AppTheme.brMd,
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.45 : 0.14),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Icon(icon, color: accent, size: 22),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (title != null)
                        Text(
                          title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(color: cs.onSurface),
                        ),
                      if (entry.message.isNotEmpty)
                        Text(
                          entry.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: title == null
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                              height: 1.3),
                        ),
                    ],
                  ),
                ),
              ),
              if (action != null)
                Center(
                  child: TextButton(
                    onPressed: () {
                      SnackBarHelper.dismissToast(entry.id);
                      action.onPressed();
                    },
                    child: Text(action.label),
                  ),
                ),
              Align(
                alignment: Alignment.topCenter,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: cs.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  // No tooltip: the host sits above the Navigator, so there
                  // is no Overlay for one to open in.
                  onPressed: () => SnackBarHelper.dismissToast(entry.id),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
