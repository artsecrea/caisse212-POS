
import 'package:cmdecrea/cmdecrea.dart';
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:posecrea/presentation/widgets/devices_management_screen.dart';
import 'package:posecrea/presentation/widgets/orders_management_screen.dart';
import 'package:posecrea/presentation/widgets/users_management_screen.dart';
import 'package:posecrea/presentation/widgets/tickets_management_screen.dart';
import 'package:posecrea/services/socket_service.dart';
import 'package:posecrea/utils/sample_data_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/database/app_database.dart';
import 'presentation/login_screen/login_screen.dart';
import 'presentation/main_screen/main_screen.dart';
import 'providers/database_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = Logger.instance;
  logger.registerHandler(const ConsoleLogHandler());

  logger.info("app started");

  final sharedPreferences = await SharedPreferences.getInstance();

  final database = AppDatabase();
  final generator = SampleDataGenerator(database);

  // Check if database is empty
  final users = await database.select(database.users).get();
  final devices = await database.select(database.kDSs).get();
  print('Users count: ${users.length}');
  print('devices count: ${devices.length}');


    // Clear all tables before seeding
    print('Clearing database...');
    await database.delete(database.tickets).go();
    await database.delete(database.orderProductComponents).go();
    await database.delete(database.orderProducts).go();
    await database.delete(database.orders).go();
    await database.delete(database.transactions).go();
    await database.delete(database.payments).go();
    await database.delete(database.cashSessions).go();
    await database.delete(database.customers).go();
    await database.delete(database.commercials).go();
    await database.delete(database.kDSs).go();
    await database.delete(database.kiosks).go();
    await database.delete(database.stations).go();
    await database.delete(database.areaTables).go();
    await database.delete(database.areas).go();
    await database.delete(database.productComponents).go();
    await database.delete(database.componentGroups).go();
    await database.delete(database.components).go();
    await database.delete(database.users).go();
    await database.delete(database.products).go();
    await database.delete(database.categories).go();

    // Generate sample data
    await generator.generateAll();
    print('Sample data generated!');



  // final s = SocketService();
  // await s.connect();


  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),

      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build( BuildContext context,WidgetRef ref,) {
    final s = ref.watch(socketServiceProvider);


    s.start(deviceId: "deviceId", deviceName: "POS", role: DeviceRole.host);

    return MaterialApp(
      title: 'POSECREA',
      builder : OnscreenKeyboard.builder(
        width: (context) => MediaQuery.sizeOf(context).width / 2,

      ),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,

          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey[50],
        ),
      ),
      home: const LoginScreen(),
      routes:{
        '/login': (context) => const LoginScreen(),
        '/main': (context) => const MainScreen(),
        '/orders': (context) => const OrdersManagementScreen(),
        '/devices': (context) => const DevicesManagementScreen(),
        '/users': (context) => const UsersManagementScreen(),
        '/tickets': (context) => const TicketsManagementScreen(),

      },
    );
  }
}