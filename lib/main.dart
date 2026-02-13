import 'package:cmdecrea/cmdecrea.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:posecrea/presentation/tenant_login_screen/tenant_login_screen.dart';
import 'package:posecrea/presentation/api_tester/api_tester_screen.dart';
import 'package:posecrea/presentation/widgets/devices_management_screen.dart';
import 'package:posecrea/presentation/widgets/orders_management_screen.dart';
import 'package:posecrea/presentation/widgets/printers_management_screen.dart';
import 'package:posecrea/presentation/widgets/sessions_management_screen.dart';
import 'package:posecrea/presentation/widgets/users_management_screen.dart';
import 'package:posecrea/presentation/widgets/tickets_management_screen.dart';
import 'package:posecrea/services/socket_service.dart';
import 'package:posecrea/services/session_service.dart';
import 'package:posecrea/services/api_service.dart';
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
  logger.registerHandler(const ConsoleLogHandler());

  logger.info("app started");

  final sharedPreferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const MyApp(),
    ),
  );
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
    final s = ref.watch(socketServiceProvider);
    final sharedPreferences = ref.watch(sharedPreferencesProvider);
    final settings = ref.watch(settingsProvider);

    // Check if user has already authenticated with server (has access token or is in demo mode)
    final accessToken = sharedPreferences.getString('server_access_token');
    final isDemoMode = sharedPreferences.getBool('is_demo_mode') ?? false;
    final hasSetup = accessToken != null || isDemoMode;

    final initialRoute = hasSetup ? '/login' : '/tenant';

    // Get POS name from SharedPreferences, use default if not set
    final posName = sharedPreferences.getString('pos_name') ?? 'POS-UNKNOWN';
    
    // Use POS name for both deviceId and deviceName
    s.start(deviceId: posName, deviceName: posName, role: DeviceRole.host);

    // Get locale from settings
    final locale = Locale(settings.language);

    return MaterialApp(
      title: 'POSECREA',
      builder : OnscreenKeyboard.builder(
        width: (context) => MediaQuery.sizeOf(context).width / 2,

      ),
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

