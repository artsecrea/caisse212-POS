import 'package:caisse212/providers/localization_provider.dart';
import 'package:caisse212/services/discovery_service.dart';
import 'package:caisse212/services/sound_service.dart';
import 'package:cmdecrea/cmdecrea.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:caisse212/presentation/tenant_login_screen/tenant_login_screen.dart';
import 'package:caisse212/presentation/api_tester/api_tester_screen.dart';
import 'package:caisse212/presentation/widgets/devices_management_screen.dart';
import 'package:caisse212/presentation/widgets/orders_management_screen.dart';
import 'package:caisse212/presentation/widgets/printers_management_screen.dart';
import 'package:caisse212/presentation/widgets/sessions_management_screen.dart';
import 'package:caisse212/presentation/widgets/users_management_screen.dart';
import 'package:caisse212/presentation/widgets/tickets_management_screen.dart';

import 'package:caisse212/services/session_service.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/server_startup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'data/database/app_database.dart';
import 'presentation/login_screen/login_screen.dart';
import 'presentation/main_screen/main_screen.dart';
import 'providers/database_providers.dart';
import 'providers/settings_provider.dart';
import 'utils/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = Logger.instance;
  logger.registerHandler(FileLogHandler(filePath: 'logs.txt'));
  logger.registerHandler(const ConsoleLogHandler());

  logger.info("app started");

  final sharedPreferences = await SharedPreferences.getInstance();

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

class GlobalSoundWrapper extends ConsumerStatefulWidget {
  final Widget child;
  const GlobalSoundWrapper({required this.child});

  @override
  ConsumerState<GlobalSoundWrapper> createState() => _GlobalSoundWrapperState();
}

class _GlobalSoundWrapperState extends ConsumerState<GlobalSoundWrapper> {
  bool _soundsEnabled = true;
  final logger = Logger.instance;

  @override
  void initState() {
    super.initState();
    // Initialize sound service but don't block UI

    _initializeSounds();
    logger.info("Sound service initialized");
    // announce the app on the network for discovery
    _appAnnounce();
  }

  Future<void> _initializeSounds() async {
    try {

      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      setState(() {
        _soundsEnabled = false;
      });
      print('Sound service initialization failed: $e');
    }
  }

  Future<void> _appAnnounce() async {

    final discoveryService = ref.read(discoveryServiceProvider);
    final settings = ref.read(settingsProvider);
    final posName = ref .read(sharedPreferencesProvider).getString('pos_name') ?? 'POS-UNKNOWN';

    final port = settings.serverPort;
    await discoveryService.announce(posName, null, port);


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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize server after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeServer();
      final soundService = ref.read(soundServiceProvider);
      await soundService.preload(); // ✅ safe
    });
  }

  Future<void> _initializeServer() async {
    try {
      final serverStartupService = ref.read(serverStartupServiceProvider);
      await serverStartupService.initializeServer();
    } catch (e) {
      print('❌ Server initialization error: $e');
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
          // print('Session ${session.id} auto-paused due to app lifecycle change');
        }
      }
    } catch (e) {
      print('Auto-pause error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sharedPreferences = ref.watch(sharedPreferencesProvider);
    final settings = ref.watch(settingsProvider);

    // Check if user has already authenticated with server (has access token or is in demo mode)
    final accessToken = sharedPreferences.getString('server_access_token');
    final isDemoMode = sharedPreferences.getBool('is_demo_mode') ?? false;
    final hasSetup = accessToken != null || isDemoMode;

    final initialRoute = hasSetup ? '/login' : '/tenant';

    // Get POS name from SharedPreferences, use default if not set
    final posName = sharedPreferences.getString('pos_name') ?? 'POS-UNKNOWN';

    final l10n = AppLocalizations.of(context);


    // Get locale from settings
    final locale = Locale(settings.language);

    return MaterialApp(
      title: 'CAISSE212',
      builder: (context, child) {
        // Update localization provider whenever context changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final l10n = AppLocalizations.of(context);
          if (l10n != null) {
            ref.read(localizationProvider.notifier).state = l10n;
          }
        });

        return OnscreenKeyboard.builder(
          width: (context) => MediaQuery.sizeOf(context).width / 2,
        )(context, child);
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
      routes:{
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
  }
}

//run flutter pub run build_runner build --delete-conflicting-outputs

// ignore_for_file: depend_on_referenced_packages

