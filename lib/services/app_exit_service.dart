import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/database_providers.dart';
import '../presentation/widgets/close_session_dialog.dart';

/// Self-contained localization for the exit flow. The app's L10n is
/// hand-written and huge; keeping these few strings here keeps the feature in
/// one file. Falls back to English for any unknown language.
const Map<String, Map<String, String>> _exitStrings = {
  'en': {
    'title': 'Exit app?',
    'body': 'Are you sure you want to close caisse212? Pending data is synced first.',
    'cancel': 'Cancel',
    'exit': 'Exit',
    'session_q': 'You have an open cash session. Close it before exiting?',
    'close_session': 'Close session',
    'leave_open': 'Leave open & exit',
    'syncing': 'Syncing before exit…',
    'exit_menu': 'Exit app',
  },
  'fr': {
    'title': 'Quitter l\'application ?',
    'body': 'Voulez-vous vraiment fermer caisse212 ? Les données en attente sont synchronisées d\'abord.',
    'cancel': 'Annuler',
    'exit': 'Quitter',
    'session_q': 'Une session de caisse est ouverte. La clôturer avant de quitter ?',
    'close_session': 'Clôturer la session',
    'leave_open': 'Laisser ouverte et quitter',
    'syncing': 'Synchronisation avant de quitter…',
    'exit_menu': 'Quitter l\'application',
  },
  'ar': {
    'title': 'إغلاق التطبيق؟',
    'body': 'هل أنت متأكد أنك تريد إغلاق caisse212؟ تتم مزامنة البيانات المعلقة أولاً.',
    'cancel': 'إلغاء',
    'exit': 'خروج',
    'session_q': 'لديك جلسة صندوق مفتوحة. هل تريد إغلاقها قبل الخروج؟',
    'close_session': 'إغلاق الجلسة',
    'leave_open': 'اتركها مفتوحة واخرج',
    'syncing': 'المزامنة قبل الخروج…',
    'exit_menu': 'إغلاق التطبيق',
  },
};

/// Localized label for an in-app "Exit app" menu entry — keeps the wording in
/// sync with the exit dialogs without touching the app-wide L10n file.
String exitMenuLabel(BuildContext context) =>
    _s(Localizations.localeOf(context).languageCode, 'exit_menu');

String _s(String lang, String key) =>
    _exitStrings[lang]?[key] ?? _exitStrings['en']![key]!;

bool get _isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

/// Large tap targets + readable text for POS touchscreens (54px tall, 17sp).
ButtonStyle _touchBtn() => ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(88, 54)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
      textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );

/// Convenience entry point for an in-app "Exit" action: runs [runAppExitFlow]
/// and, if confirmed, actually closes the app for the current platform.
///
/// (The desktop window-close handler in `main.dart` calls [runAppExitFlow]
/// directly because it also has to flip `setPreventClose` around `destroy`.)
Future<void> requestAppExit(BuildContext context, WidgetRef ref) async {
  final shouldExit = await runAppExitFlow(context, ref);
  if (!shouldExit) return;
  await hardExitApp();
}

/// Actually terminates the app for the current platform.
///
/// On desktop the app keeps an embedded HTTP server (open socket), mDNS
/// advertisement, an SSE/websocket client and a periodic sync timer alive —
/// all of which keep the Dart isolate running. Because of that,
/// `windowManager.destroy()` on its own can tear down the native window yet
/// leave the process hung and "not responding" (the reported freeze on quit).
///
/// So we fire the graceful destroy but do NOT await it, give it a brief moment
/// to close the window, then force `exit(0)` to guarantee the process really
/// terminates. (Pending data was already flushed by [runAppExitFlow]; anything
/// still unsynced stays queued and flushes on next launch.) Mobile just pops.
Future<void> hardExitApp() async {
  if (_isDesktop) {
    try {
      await windowManager.setPreventClose(false);
      // Not awaited — destroy() can block while the server/sockets/timers hold
      // the isolate open; exit(0) below is the guaranteed teardown.
      unawaited(windowManager.destroy());
    } catch (_) {/* fall through to exit(0) */}
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  } else {
    await SystemNavigator.pop();
  }
}

/// Runs the interactive app-exit flow and returns `true` when the app may
/// actually close, `false` if the user cancelled at any point.
///
/// Steps: (1) confirm, (2) if a cash session is open, offer to close it via the
/// Z-report dialog or leave it open, (3) best-effort sync bounded to 15s (exit
/// proceeds regardless — unsynced rows stay queued and flush on next launch).
///
/// Shared by every exit path (desktop window close, in-app Exit button, mobile
/// back-to-exit) so the behavior is identical everywhere.
Future<bool> runAppExitFlow(BuildContext context, WidgetRef ref) async {
  final lang = Localizations.localeOf(context).languageCode;
  String s(String k) => _s(lang, k);

  // 1. Exit confirmation.
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      title: Row(
        children: [
          const Icon(Icons.power_settings_new, color: Colors.redAccent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(s('title'),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      content: Text(s('body'), style: const TextStyle(fontSize: 17, height: 1.4)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actions: [
        OutlinedButton(
          style: _touchBtn(),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s('cancel')),
        ),
        FilledButton(
          style: _touchBtn(),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(s('exit')),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  // 2. Offer to close an open cash session (Z-report). Non-fatal on error —
  //    we never want a session-lookup failure to trap the user in the app.
  try {
    final user = ref.read(currentUserProvider);
    if (user != null && context.mounted) {
      final session =
          await ref.read(sessionQueriesProvider).getActiveSession(user.id);
      if (session != null && session.status == 'active' && context.mounted) {
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            title: Row(
              children: [
                const Icon(Icons.point_of_sale, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(s('close_session'),
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            // Choices as full-width, tall buttons — each an easy touch target,
            // instead of three cramped buttons in the actions row.
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s('session_q'),
                    style: const TextStyle(fontSize: 17, height: 1.4)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: _touchBtn(),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(s('close_session')),
                    onPressed: () => Navigator.pop(ctx, 'close'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: _touchBtn(),
                    icon: const Icon(Icons.logout),
                    label: Text(s('leave_open')),
                    onPressed: () => Navigator.pop(ctx, 'leave'),
                  ),
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actions: [
              TextButton(
                style: _touchBtn(),
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: Text(s('cancel')),
              ),
            ],
          ),
        );
        if (choice == null || choice == 'cancel') return false;
        if (choice == 'close' && context.mounted) {
          final result = await showCloseSessionDialog(
            context: context,
            ref: ref,
            sessionId: session.id,
          );
          // Backed out of the Z-report → abort the whole exit so nothing is
          // half-done.
          if (!result.closed) return false;
        }
      }
    }
  } catch (_) {
    // proceed to sync + exit
  }

  // 3. Best-effort sync, bounded so a slow/unreachable server can't hang exit.
  if (context.mounted) {
    await _syncBeforeExit(context, ref, s('syncing'));
  }
  return true;
}

/// Pushes locally-queued rows before exit, showing a blocking spinner capped at
/// 15s. Only PUSHES (via [SyncJobService.flushForExit]) — never pulls server
/// deltas — and skips the whole thing (no spinner, instant exit) when nothing
/// is unsynced, so a clean exit doesn't hang. Any failure/timeout is swallowed:
/// the offline-first design keeps unsynced rows queued to flush on next launch.
Future<void> _syncBeforeExit(
    BuildContext context, WidgetRef ref, String label) async {
  final syncJob = ref.read(syncJobServiceProvider);

  // Nothing queued (or offline) → don't block exit or flash a spinner.
  if (!await syncJob.hasPendingForExit()) return;

  var spinnerShown = false;
  if (context.mounted) {
    spinnerShown = true;
    // Not awaited — we drive dismissal ourselves once sync settles.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 20),
              Flexible(
                child: Text(label, style: const TextStyle(fontSize: 17)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  try {
    await syncJob.flushForExit().timeout(const Duration(seconds: 15));
  } catch (_) {
    // offline / timeout / server error → exit anyway
  }

  if (spinnerShown && context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}
