import 'dart:io';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/routes/app_pages.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/hid_wedge_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Dark-mode on-secondary (near-black) — secondary swatch sits on light text in dark mode.
const Color _kDarkOnSecondary = Color(0xFF0B1116);

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

  // Permission service must be registered before AuthenticationController so
  // fetchUserDetails can call prefetchAll on login / app restart.
  Get.put<PermissionService>(PermissionService(), permanent: true);

  // Hardware scan services — registered here (not in HomeBinding) so that
  // the EventChannel stream listener is live before the first scan can
  // arrive from the native BroadcastReceiver in MainActivity.
  Get.put<DataWedgeService>(DataWedgeService(), permanent: true);
  // HID keyboard-wedge bridge (Netum C750 etc.) feeds DataWedgeService.scannedCode.
  Get.put<HidWedgeService>(HidWedgeService(), permanent: true);
  Get.put<ScanService>(ScanService(), permanent: true);

  Get.put<AuthenticationController>(AuthenticationController(), permanent: true);

  Get.put<ThemeController>(ThemeController(), permanent: true);
  await Get.find<ThemeController>().loadPersisted();

  final authController = Get.find<AuthenticationController>();
  await authController.checkAuthenticationStatus();

  runApp(MultimaxApp(initialRoute: authController.isAuthenticated.value
      ? AppRoutes.HOME
      : AppRoutes.LOGIN));
}

/// Builds a [ThemeData] from a semantic [AppScheme]. Used for both the light
/// and dark themes so the two can never drift. Keeps the maroon brand primary.
ThemeData buildAppTheme(AppScheme scheme, Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: scheme.primary,
    brightness: brightness,
    primary: scheme.primary,
    onPrimary: scheme.onPrimary,
    secondary: scheme.secondary,
    onSecondary: brightness == Brightness.dark
        ? _kDarkOnSecondary
        : Colors.white,
    surface: scheme.fg,
    onSurface: scheme.text,
    outline: scheme.borderStrong,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Inter',
    colorScheme: colorScheme,
    // In dark mode ThemeData defaults primaryColor to colorScheme.surface (a
    // dark grey), so anything painted with Theme.of(context).primaryColor — the
    // drawer header, selected nav items — turns invisible against dark surfaces.
    // Pin it to the brand so it stays maroon (lightened on dark) in both modes.
    primaryColor: scheme.primary,
    scaffoldBackgroundColor: scheme.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      centerTitle: false,
      elevation: 0,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.textMuted,
      indicatorColor: scheme.primary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.secondary,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.secondary,
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: Colors.white,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md)),
    ),
    cardTheme: CardThemeData(
      color: scheme.fg,
      elevation: brightness == Brightness.dark ? 0 : 1,
      surfaceTintColor: scheme.fg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: scheme.border, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.fg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.textMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.primary),
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    textTheme: TextTheme(
      titleLarge:
          TextStyle(color: scheme.text, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(color: scheme.text),
    ),
  );
}

class MultimaxApp extends StatelessWidget {
  final String initialRoute;

  const MultimaxApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    final themeController = Get.isRegistered<ThemeController>()
        ? Get.find<ThemeController>()
        : Get.put(ThemeController());

    // Source of truth for the active theme is this Obx binding on
    // themeController.themeMode; ThemeController also calls
    // Get.changeThemeMode so GetX-internal consumers stay in sync.
    return Obx(() => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'KA-ML Fulfillment',
          initialRoute: initialRoute,
          getPages: AppPages.routes,
          theme: buildAppTheme(AppScheme.light, Brightness.light),
          darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark),
          themeMode: themeController.themeMode.value,
          defaultTransition: Transition.fadeIn,
          routingCallback: (routing) {
            if (routing?.current != null &&
                Get.isRegistered<HomeController>()) {
              Get.find<HomeController>().updateActiveScreen(routing!.current);
            }
          },
        ));
  }
}
