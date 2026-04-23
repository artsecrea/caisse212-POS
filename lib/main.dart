import 'dart:io';
import 'dart:async';
import 'package:caisse212/presentation/widgets/printers_management_screen.dart';
import 'package:caisse212/providers/desktop_update_provider.dart';
import 'package:caisse212/providers/localization_provider.dart';
import 'package:caisse212/services/discovery_service.dart';
import 'package:caisse212/services/sound_service.dart';
import 'package:desktop_updater/desktop_updater.dart';
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

import 'package:caisse212/services/session_service.dart';
import 'package:caisse212/services/server_startup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'core/theme/app_theme.dart';
import 'presentation/login_screen/login_screen.dart';
import 'presentation/main_screen/main_screen.dart';
import 'providers/database_providers.dart';
import 'providers/settings_provider.dart';
import 'utils/app_localizations.dart';

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
                  color: Colors.grey[600],
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
    // Show a loading screen immediately to prevent blank white screen
    runApp(const _BootScreen());

    // Initialize window manager for desktop platforms (fullscreen support)
    if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      try {
        await windowManager.ensureInitialized();
        await windowManager.waitUntilReadyToShow(null, () async {
          await windowManager.show();
          await windowManager.focus();
        }).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('⚠️ Window manager timed out, continuing anyway');
          },
        );
      } catch (e) {
        debugPrint('Window manager init failed: $e');
      }
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
                const Text('Please restart the application.',
                  style: TextStyle(color: Colors.grey),
                ),
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

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {

  final logger = Logger.instance;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
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

    // Desktop updater controller (null on non-desktop or before login)
    final desktopUpdaterController =
        ref.watch(desktopUpdaterControllerProvider);

    final app = MaterialApp(
      title: 'CAISSE212',
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
          result = OnscreenKeyboard.builder(
            width: (context) => MediaQuery.sizeOf(context).width / 2,
          )(context, child);
        } catch (e) {
          debugPrint('OnscreenKeyboard builder failed: $e');
          result = child ?? const SizedBox.shrink();
        }

        // Overlay the update dialog listener on desktop when controller is available.
        // UpdateDialogListener has no child parameter – it renders as a floating overlay.
        if (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux) &&
            desktopUpdaterController != null) {
          result = Stack(
            children: [
              result,
              UpdateDialogListener(controller: desktopUpdaterController),
            ],
          );
        }

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
      },
    );

    return app;
  }
}

//run flutter pub run build_runner build --delete-conflicting-outputs

// ignore_for_file: depend_on_referenced_packages

