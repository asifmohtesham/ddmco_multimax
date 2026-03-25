import 'dart:io';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_pages.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set up the database factory for desktop platforms.
  if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) && !kIsWeb) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialise services & global controllers.
  await Get.putAsync<DatabaseService>(() => DatabaseService().init());
  await Get.putAsync<ApiProvider>(() async => ApiProvider(), permanent: true);

  // Hardware scan services — registered here (not in HomeBinding) so that
  // the EventChannel stream listener is live before the first scan can
  // arrive from the native BroadcastReceiver in MainActivity.
  Get.put<DataWedgeService>(DataWedgeService(), permanent: true);
  Get.put<ScanService>(ScanService(), permanent: true);

  Get.put<AuthenticationController>(AuthenticationController(), permanent: true);

  final authController = Get.find<AuthenticationController>();
  await authController.checkAuthenticationStatus();

  runApp(MultimaxApp(initialRoute: authController.isAuthenticated.value
      ? AppRoutes.HOME
      : AppRoutes.LOGIN));
}

class MultimaxApp extends StatelessWidget {
  final String initialRoute;

  const MultimaxApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    const Color primaryColour    = Color(0xFF870E18);
    const Color secondaryColour  = Color(0xFF25286F);
    const Color greyColour       = Color(0xFF6F6D6E);
    const Color backgroundColour = Color(0xFFF5F5F5);

    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KA-ML Fulfillment',
      initialRoute: initialRoute,
      getPages: AppPages.routes,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColour,
          primary: primaryColour,
          secondary: secondaryColour,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          outline: greyColour,
        ),
        scaffoldBackgroundColor: backgroundColour,
        appBarTheme: const AppBarTheme(
          backgroundColor: primaryColour,
          foregroundColor: Colors.white,
          centerTitle: false,
          elevation: 0,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: TextStyle(fontWeight: FontWeight.bold),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: secondaryColour,
          foregroundColor: Colors.white,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: secondaryColour,
          contentTextStyle: TextStyle(color: Colors.white),
          actionTextColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8))),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: greyColour.withValues(alpha: .2), width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: greyColour),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                BorderSide(color: greyColour.withValues(alpha: .5)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: primaryColour, width: 2),
          ),
          labelStyle: const TextStyle(color: greyColour),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColour,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(
                vertical: 16, horizontal: 24),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: secondaryColour),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: const TextTheme(
          titleLarge: TextStyle(
              color: secondaryColour, fontWeight: FontWeight.bold),
          bodyMedium: TextStyle(color: Color(0xFF333333)),
        ),
      ),
      defaultTransition: Transition.fadeIn,
      routingCallback: (routing) {
        if (routing?.current != null &&
            Get.isRegistered<HomeController>()) {
          Get.find<HomeController>()
              .updateActiveScreen(routing!.current);
        }
      },
    );
  }
}
