import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/database_providers.dart';
import '../presentation/widgets/close_session_dialog.dart';
import 'session_service.dart';

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

/// Convenience entry point for an in-app "Exit" action: runs [runAppExitFlow]
/// and, if confirmed, actually closes the app for the current platform.
///
/// (The desktop window-close handler in `main.dart` calls [runAppExitFlow]
/// directly because it also has to flip `setPreventClose` around `destroy`.)
Future<void> requestAppExit(BuildContext context, WidgetRef ref) async {
  final shouldExit = await runAppExitFlow(context, ref);
  if (!shouldExit) return;
  if (_isDesktop) {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
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
      title: Text(s('title')),
      content: Text(s('body')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s('cancel')),
        ),
        FilledButton(
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
          await SessionService(ref.read(databaseProvider)).getActiveSession(user.id);
      if (session != null && session.status == 'active' && context.mounted) {
        final choice = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(s('close_session')),
            content: Text(s('session_q')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: Text(s('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'leave'),
                child: Text(s('leave_open')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'close'),
                child: Text(s('close_session')),
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

/// Shows a blocking spinner while [SyncJobService.syncNow] runs, capped at 15s.
/// Any failure/timeout is swallowed: the offline-first design keeps unsynced
/// rows queued (`is_synced = false`) to flush on the next launch.
Future<void> _syncBeforeExit(
    BuildContext context, WidgetRef ref, String label) async {
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
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(label)),
            ],
          ),
        ),
      ),
    );
  }

  try {
    await ref
        .read(syncJobServiceProvider)
        .syncNow()
        .timeout(const Duration(seconds: 15));
  } catch (_) {
    // offline / timeout / server error → exit anyway
  }

  if (spinnerShown && context.mounted) {
    Navigator.of(context, rootNavigator: true).pop();
  }
}
