import 'dart:io';
import 'dart:async';
import 'package:caisse212/presentation/widgets/printers_management_screen.dart';
import 'package:caisse212/presentation/widgets/update_ready_banner.dart';
import 'package:caisse212/presentation/widgets/reauth_overlay.dart';
import 'package:caisse212/providers/reauth_provider.dart';
import 'package:caisse212/services/update_service.dart';
import 'package:caisse212/providers/localization_provider.dart';
import 'package:caisse212/services/discovery_service.dart';
import 'package:caisse212/services/sound_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:caisse212/presentation/tenant_login_screen/tenant_login_screen.dart';
import 'package:caisse212/presentation/api_tester/api_tester_screen.dart';
import 'package:caisse212/presentation/widgets/devices_management_screen.dart';
import 'package:caisse212/presentation/widgets/orders_management_screen.dart';
import 'package:caisse212/presentation/widgets/sessions_management_screen.dart';
import 'package:caisse212/presentation/widgets/users_management_screen.dart';
import 'package:caisse212/presentation/widgets/tickets_management_screen.dart';
import 'package:caisse212/presentation/widgets/agenda_screen.dart';
import 'presentation/booking/booking_screen.dart';
import 'package:caisse212/presentation/widgets/dashboard_screen.dart';
import 'package:caisse212/presentation/widgets/notes_screen.dart';
import 'package:caisse212/presentation/widgets/logs_screen.dart';
import 'package:caisse212/services/session_service.dart';
import 'package:caisse212/services/server_startup_service.dart';
import 'package:caisse212/services/activity_log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/autostart_service.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'presentation/login_screen/login_screen.dart';
import 'presentation/main_screen/main_screen.dart';
import 'providers/database_providers.dart';
import 'providers/settings_provider.dart';import 'utils/app_localizations.dart';
import 'services/app_exit_service.dart';
import 'providers/sse_provider.dart';

/// Global navigator key — lets the desktop window-close handler (which runs
/// outside any widget's build context) obtain a dialog-capable context to drive
/// the app-exit flow.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Initialize Flutter bindings in the root zone to avoid zone mismatch.
  WidgetsFlutterBinding.ensureInitialized();

  // Set up error handling for Flutter errors early.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _logError('FlutterError', details.exception, details.stack);
  };

  // Catch all other uncaught platform/async errors without spawning a new zone.
  PlatformDispatcher.instance.onError = (error, stack) {
    _logError('PlatformError', error, stack);
    return false;
  };

  // Apply any prepared update before the UI starts.
  // If an update is ready, this launches the updater script and calls exit(0).
  await UpdateService.applyPendingUpdateIfExists();

  // Call directly (same zone as ensureInitialized) to avoid zone mismatch.
  await _initializeApp();
}

/// Boot screen shown while the app initializes
class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _initializeApp() async {
    final isDesktop =
        !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

    // Initialize window_manager so later calls work (the fullscreen toggle in
    // the login screen, focus below). We deliberately do NOT resize or maximize
    // the window from Dart: the native runner creates it already maximized (see
    // win32_window.cpp), so the Flutter engine's view is built at the final size
    // and there is no startup resize. Maximizing from Dart here would resize the
    // window after the engine view already exists, which renders the UI at the
    // old default size inside a full-screen window (compressed UI + black area)
    // until a manual resize.
    if (isDesktop) {
      try {
        await windowManager.ensureInitialized();
      } catch (e) {
        debugPrint('Window manager init failed: $e');
      }
    }

    // Show a loading screen immediately to prevent a blank white screen. Its
    // first frame triggers the native show — the window is already maximized.
    runApp(const _BootScreen());

    // Bring the window to the foreground once it is shown. Fire-and-forget so
    // it never blocks startup.
    if (isDesktop) {
      unawaited(windowManager.focus());
    }


    final logger = Logger.instance;

    // Initialize logger with safe path
    try {
      final logPath = await _getLogFilePath();
      logger.registerHandler(FileLogHandler(filePath: logPath));
    } catch (e) {
      // If file logging fails, continue without it
      debugPrint('Failed to initialize file logging: $e');
    }
    logger.registerHandler(const ConsoleLogHandler());

    logger.info("App starting...");
    logger.info("Platform: ${Platform.operatingSystem}");
    logger.info("Release mode: $kReleaseMode");

    SharedPreferences? sharedPreferences;
    try {
      sharedPreferences = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('SharedPreferences timed out');
        },
      );
      logger.info("SharedPreferences initialized");

      // Keep the OS autostart entry honest. The registered path is
      // absolute, so an update that moved the executable leaves an entry
      // pointing at a file that is gone; rewriting it on every launch is
      // the only thing that repairs that. Fire-and-forget - a till that
      // cannot write its own autostart entry must still open.
      if (isDesktop) {
        final wantsAutostart =
            sharedPreferences.getBool('open_on_startup') ??
                (sharedPreferences.getString('api_base_url') == null);
        unawaited(AutostartService.reconcile(wantsAutostart));
      }
    } catch (e, stack) {
      logger.error("Failed to initialize SharedPreferences: $e");
      _logError('SharedPreferences', e, stack);
      // Show error UI instead of crashing
      runApp(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Failed to initialize: $e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                // No context to read a theme from here — this screen is built
                // outside the widget tree. Inherit the default text colour.
                const Text('Please restart the application.'),
              ],
            ),
          ),
        ),
      ));
      return;
    }

    logger.info("Starting app...");

    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
        child: const GlobalSoundWrapper(
          child: MyApp(),
        ),
      ),
    );
}

/// Get a safe log file path that works in release mode
Future<String> _getLogFilePath() async {
  if (Platform.isWindows) {
    try {
      // Try using the executable directory for logs on Windows
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent.path;
      final logPath = '$exeDir\\logs.txt';
      // Test if writable
      final testFile = File(logPath);
      await testFile.writeAsString('', mode: FileMode.append);
      return logPath;
    } catch (_) {
      // Fall back to temp directory
      final tempDir = Directory.systemTemp.path;
      return '$tempDir\\posecrea_logs.txt';
    }
  }
  return 'logs.txt';
}

/// Log errors to a file for debugging release builds
void _logError(String source, Object error, StackTrace? stack) {
  try {
    final timestamp = DateTime.now().toIso8601String();
    final message = '''
=== ERROR [$source] at $timestamp ===
Error: $error
Stack: ${stack ?? 'No stack trace'}
=====================================

''';

    debugPrint(message);

    // Try to write to error log file
    if (Platform.isWindows) {
      try {
        final exePath = Platform.resolvedExecutable;
        final exeDir = File(exePath).parent.path;
        final errorLogPath = '$exeDir\\error_log.txt';
        File(errorLogPath).writeAsStringSync(message, mode: FileMode.append);
      } catch (_) {}
    }
  } catch (_) {
    // Ignore logging errors
  }
}

class GlobalSoundWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const GlobalSoundWrapper({super.key, required this.child});

  @override
  ConsumerState<GlobalSoundWrapper> createState() => _GlobalSoundWrapperState();
}

class _GlobalSoundWrapperState extends ConsumerState<GlobalSoundWrapper> {
  bool _soundsEnabled = true;
  bool _initialized = false;
  final logger = Logger.instance;

  @override
  void initState() {
    super.initState();
    // Defer initialization to after the first frame to ensure providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safeInitialize();
    });
  }

  Future<void> _safeInitialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      await _initializeSounds().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          logger.warning("Sound initialization timed out");
        },
      );
      logger.info("Sound service initialized");
    } catch (e) {
      logger.warning("Sound service initialization failed: $e");
      if (mounted) {
        setState(() {
          _soundsEnabled = false;
        });
      }
    }

    try {
      await _appAnnounce().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          logger.warning("App announce timed out");
        },
      );
    } catch (e) {
      logger.warning("App announce failed: $e");
    }
  }

  Future<void> _initializeSounds() async {
    try {
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      if (mounted) {
        setState(() {
          _soundsEnabled = false;
        });
      }
      logger.info('Sound service initialization failed: $e');
    }
  }

  Future<void> _appAnnounce() async {
    if (!mounted) return;

    try {
      final discoveryService = ref.read(discoveryServiceProvider);
      final settings = ref.read(settingsProvider);
      final posName = ref.read(sharedPreferencesProvider).getString('pos_name') ?? 'POS-UNKNOWN';

      final port = settings.serverPort;
      await discoveryService.announce(posName, null, port);
    } catch (e) {
      logger.warning('App announce failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_soundsEnabled) {
      // Return child without sound wrapper if sounds are disabled
      return widget.child;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        try {
          ref.read(soundServiceProvider).gestureTap();
        } catch (e) {
          // Silently fail if sound service has issues
        }
      },
      child: widget.child,
    );
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp>
    with WidgetsBindingObserver, WindowListener {

  final logger = Logger.instance;

  /// True while [onWindowClose] is driving the exit flow — guards against the
  /// user clicking the window's X repeatedly and stacking dialogs.
  bool _handlingExit = false;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Desktop: intercept the OS window-close (X) so we can confirm, offer to
    // close the cash session, and sync before actually destroying the window.
    if (_isDesktop) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
    // Initialize server after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _initializeServer().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            logger.info('⚠️ Server initialization timed out');
          },
        );
      } catch (e) {
        logger.info('❌ Server init error: $e');
      }
      try {
        final soundService = ref.read(soundServiceProvider);
        await soundService.preload().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('⚠️ Sound preload timed out');
          },
        );
      } catch (e) {
        debugPrint('Sound preload failed: $e');
      }
      // Roll the activity log once per day (export old entries to Desktop, purge).
      try {
        await ref.read(activityLogServiceProvider).purgeIfDue();
      } catch (e) {
        debugPrint('Activity-log purge failed: $e');
      }
    });
  }

  Future<void> _initializeServer() async {
    try {
      final serverStartupService = ref.read(serverStartupServiceProvider);
      await serverStartupService.initializeServer();
    } catch (e) {
      logger.info('❌ Server initialization error: $e');
    }
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Desktop window-close (X) handler. Because we set `preventClose = true`,
  /// the window won't close on its own — we run the shared exit flow and only
  /// destroy the window if the user confirms.
  @override
  void onWindowClose() async {
    if (_handlingExit) return;
    _handlingExit = true;
    try {
      final ctx = appNavigatorKey.currentContext;
      // No context yet (still booting) → just let it close.
      final shouldExit = ctx == null ? true : await runAppExitFlow(ctx, ref);
      if (shouldExit) {
        await hardExitApp();
      }
    } catch (e) {
      logger.error('Window-close exit flow failed: $e');
      // Don't trap the user — force the close.
      await hardExitApp();
    } finally {
      _handlingExit = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Auto-pause session when app goes to background or is paused
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _autoPauseSession();
    }
  }

  Future<void> _autoPauseSession() async {
    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser != null) {
        final database = ref.read(databaseProvider);
        final sessionService = SessionService(database);
        final session = await sessionService.getActiveSession(currentUser.id);

        if (session != null && session.status == 'active') {
          // await sessionService.pauseSession(session.id);
          // logger.info('Session ${session.id} auto-paused due to app lifecycle change');
        }
      }
    } catch (e) {
      logger.info('Auto-pause error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return _buildApp(context);
    } catch (e, stack) {
      logger.error('Fatal error building app: $e');
      _logError('AppBuild', e, stack);
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('Application Error',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('$e',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      // Force rebuild
                      setState(() {});
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  Widget _buildApp(BuildContext context) {
    final sharedPreferences = ref.watch(sharedPreferencesProvider);
    final settings = ref.watch(settingsProvider);

    // Check if user has already authenticated with server (has access token or is in demo mode)
    final accessToken = sharedPreferences.getString('server_access_token');
    final isDemoMode = sharedPreferences.getBool('is_demo_mode') ?? false;
    final hasSetup = accessToken != null || isDemoMode;

    final initialRoute = hasSetup ? '/login' : '/tenant';

    // Get locale from settings
    final locale = Locale(settings.language);

    // Keep the order-queue subscription alive for as long as the app runs, not
    // just while the till screen is open. Two reasons: an order arriving while
    // the cashier sits in Settings or Orders would otherwise be missed
    // entirely, and the server alerts the admin with "0 terminals reached"
    // whenever nobody is subscribed — which was true every time someone
    // navigated away. The provider is a no-op when SSE is disabled or no user
    // is logged in, so this costs nothing on a terminal that does not use it.
    ref.watch(sseLifecycleProvider);

    final app = MaterialApp(
      title: 'caisse212',
      navigatorKey: appNavigatorKey,
      builder: (context, child) {
        // Update localization provider whenever context changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            final l10n = AppLocalizations.of(context);
            if (l10n != null) {
              ref.read(localizationProvider.notifier).state = l10n;
            }
          } catch (_) {}
        });

        Widget result;
        try {
          final showKeyboard = ref.read(showOnscreenKeyboardProvider);
          final keyboardWidth = ref.read(onscreenKeyboardWidthFractionProvider);
          if (showKeyboard) {
            result = OnscreenKeyboard.builder(
              width: (context) => MediaQuery.sizeOf(context).width * keyboardWidth,
            )(context, child);
          } else {
            result = child ?? const SizedBox.shrink();
          }
        } catch (e) {
          debugPrint('OnscreenKeyboard builder failed: $e');
          result = child ?? const SizedBox.shrink();
        }

        // Global "update ready" banner (auto-update flow): a slim bar pinned
        // above the app content that appears once a non-mandatory update has
        // been silently downloaded, offering Restart-now / Later. Renders an
        // empty box when there's nothing to show, so this is a no-op most of
        // the time. (The legacy `desktop_updater` overlay was removed — the app
        // uses the signed UpdateService flow against caisse212-updates.)
        result = Column(
          children: [
            const UpdateReadyBanner(),
            Expanded(child: result),
          ],
        );

        // Mobile back-to-exit: this PopScope sits ABOVE the Navigator, so
        // in-app back is handled by the Navigator first and only a root-level
        // back (nothing left to pop) bubbles up here to run the exit flow.
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          result = PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              final ctx = appNavigatorKey.currentContext ?? context;
              final shouldExit = await runAppExitFlow(ctx, ref);
              if (shouldExit) {
                await hardExitApp();
              }
            },
            child: result,
          );
        }

        // Obligatory re-auth gate — the topmost overlay, so it blocks the whole
        // app when the terminal's session (refresh token) is expiring/expired.
        // Re-authenticates in place (no navigation, state preserved); "Sign out"
        // is the escape hatch to the tenant login.
        result = Stack(
          children: [
            result,
            ReauthOverlay(
              onSignOut: () async {
                final api = ref.read(apiServiceProvider);
                await api.clearAllAuthData();
                ref.read(currentUserProvider.notifier).state = null;
                ref.read(currentSessionProvider.notifier).state = null;
                ref.read(reauthRequiredProvider.notifier).reevaluate();
                appNavigatorKey.currentState
                    ?.pushNamedAndRemoveUntil('/tenant', (r) => false);
              },
            ),
          ],
        );

        return result;
      },
      debugShowCheckedModeBanner: false,

      // Localization configuration
      locale: locale,

      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en', ''), // English
        Locale('ar', ''), // Arabic
        Locale('fr', ''), // French
        Locale('es', ''), // Spanish
      ],

      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      initialRoute: initialRoute,
      routes: {
        '/tenant': (context) => const TenantLoginScreen(),
        '/tenant_login': (context) => const TenantLoginScreen(),
        '/login': (context) => const LoginScreen(),
        '/main': (context) => const MainScreen(),
        '/orders': (context) => const OrdersManagementScreen(),
        '/devices': (context) => const DevicesManagementScreen(),
        '/users': (context) => const UsersManagementScreen(),
        '/tickets': (context) => const TicketsManagementScreen(),
        '/sessions': (context) => const SessionsManagementScreen(),
        '/printers': (context) => const PrintersManagementScreen(),
        '/api-tester': (context) => const ApiTesterScreen(),
        '/agenda': (context) => const AgendaScreen(),
        '/booking': (context) => const BookingScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/notes': (context) => const NotesScreen(),
        '/logs': (context) => const LogsScreen(),
      },
    );

    return app;
  }
}

//run flutter pub run build_runner build --delete-conflicting-outputs

// ignore_for_file: depend_on_referenced_packages

