import 'dart:async' show unawaited;
import 'dart:io';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/routes/app_pages.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/digest_scheduler.dart';
import 'package:multimax/app/data/services/digest_worker.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/home/home_controller.dart';
import 'package:multimax/app/modules/theme/theme_controller.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/data_wedge_service.dart';
import 'package:multimax/app/data/services/hid_wedge_service.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get_storage/get_storage.dart';
import 'package:workmanager/workmanager.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

/// Dark-mode on-secondary (near-black) — secondary swatch sits on light text in dark mode.
const Color _kDarkOnSecondary = Color(0xFF0B1116);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Backs every StorageService preference (session defaults, auto-submit,
  // Stock Balance toggles, dashboard layout…). Without this call GetStorage
  // runs purely in memory and all of those silently reset on app restart.
  await GetStorage.init();

  // Timezone DB for iOS scheduled digest reminders (zonedSchedule throws
  // without tz.local set). iOS-only — Android uses WorkManager, not
  // zonedSchedule. Best-effort — a failure here must never block startup.
  if (!kIsWeb && Platform.isIOS) {
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Leaves tz.local unset; iOS reminder scheduling will no-op on failure.
    }
  }

  // Scheduled digest notifications (Android-only). Registers the background
  // dispatcher; actual work is only ever scheduled by DigestScheduler.
  if (!kIsWeb && Platform.isAndroid) {
    await Workmanager().initialize(digestCallbackDispatcher);
  }

  // Set up the database factory for desktop platforms.
  if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) && !kIsWeb) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialise services & global controllers.
  await Get.putAsync<DatabaseService>(() => DatabaseService().init());

  // Mirror the configured server URL (persisted in SQLite) into GetStorage so
  // the background digest isolate — which has no DatabaseService — can resolve
  // the correct instance. Without this it would always fall back to the default
  // host and produce false "Session expired" digests for instance-switchers.
  if (!kIsWeb && Platform.isAndroid) {
    final serverUrl =
        await Get.find<DatabaseService>().getConfig(DatabaseService.serverUrlKey);
    if (serverUrl != null && serverUrl.isNotEmpty) {
      await StorageService().saveBaseUrl(serverUrl);
    }
  }

  await Get.putAsync<ApiProvider>(() async => ApiProvider(), permanent: true);

  // Permission service must be registered before AuthenticationController so
  // fetchUserDetails can call prefetchAll on login / app restart.
  Get.put<PermissionService>(PermissionService(), permanent: true);

  // Hardware scan services — registered here (not in HomeBinding) so that
  // the EventChannel stream listener is live before the first scan can
  // arrive from the native BroadcastReceiver in MainActivity.
  Get.put<DataWedgeService>(DataWedgeService(), permanent: true);
  // HID keyboard-wedge bridge (Netum C750 etc.) feeds DataWedgeService.scannedCode.
  // Android-only: the service attaches a global HardwareKeyboard handler that
  // classifies fast keystrokes as scanner bursts. On iOS / desktop the Mac/PC
  // keyboard would trigger the same path, eating characters from focused text
  // fields — and there is no Bluetooth HID scanner workflow there to justify it.
  if (Platform.isAndroid) {
    Get.put<HidWedgeService>(HidWedgeService(), permanent: true);
  }
  Get.put<ScanService>(ScanService(), permanent: true);

  Get.put<AuthenticationController>(AuthenticationController(), permanent: true);

  Get.put<ThemeController>(ThemeController(), permanent: true);
  await Get.find<ThemeController>().loadPersisted();

  final authController = Get.find<AuthenticationController>();
  await authController.checkAuthenticationStatus();

  // Self-heal the digest schedule on every launch (Android: WorkManager chain;
  // iOS: the weekly reminder set). Fire-and-forget — startup never blocks.
  if (!kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      authController.isAuthenticated.value) {
    unawaited(DigestScheduler().rearm().catchError((_) {}));
  }

  runApp(MultimaxApp(initialRoute: authController.isAuthenticated.value
      ? AppRoutes.HOME
      : AppRoutes.LOGIN));
}

/// Builds a [ThemeData] from a semantic [AppScheme]. Used for both the light
/// and dark themes so the two can never drift. Keeps the maroon brand primary.
ThemeData buildAppTheme(
  AppScheme scheme,
  Brightness brightness, {
  AppAccent accent = AppAccent.brand,
}) {
  // The accent supplies the primary; the brand maroon is the default. All
  // neutrals/surfaces still come from [scheme].
  final primary = accent.primaryFor(brightness);
  final onPrimary = accent.onPrimaryFor(brightness);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
    primary: primary,
    onPrimary: onPrimary,
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
    primaryColor: primary,
    scaffoldBackgroundColor: scheme.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: primary,
      foregroundColor: onPrimary,
      centerTitle: false,
      elevation: 0,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: primary,
      unselectedLabelColor: scheme.textMuted,
      indicatorColor: primary,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: scheme.border,
      labelStyle: const TextStyle(fontWeight: FontWeight.w500),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
    ),
    // Secondary flips to a LIGHT indigo in dark mode, so anything sitting on
    // it must use onSecondary (near-black in dark), not hardcoded white —
    // white-on-#8C8FE0 is 2.95:1 and fails WCAG.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.secondary,
      foregroundColor: colorScheme.onSecondary,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.secondary,
      contentTextStyle: TextStyle(color: colorScheme.onSecondary),
      actionTextColor: colorScheme.onSecondary,
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
        borderSide: BorderSide(color: primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.textMuted),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primary),
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
    // themeController's themeMode/accentKey/textSize; ThemeController also calls
    // Get.changeThemeMode so GetX-internal consumers stay in sync.
    return Obx(() {
      final accent = AppAccent.byKey(themeController.accentKey.value);
      final textFactor = themeController.textSize.value.factor;
      return GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Multimax',
        initialRoute: initialRoute,
        getPages: AppPages.routes,
        theme: buildAppTheme(AppScheme.light, Brightness.light, accent: accent),
        darkTheme: buildAppTheme(AppScheme.dark, Brightness.dark, accent: accent),
        themeMode: themeController.themeMode.value,
        defaultTransition: Transition.fadeIn,
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: TextScaler.linear(textFactor)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        routingCallback: (routing) {
          if (routing?.current != null &&
              Get.isRegistered<HomeController>()) {
            Get.find<HomeController>().updateActiveScreen(routing!.current);
          }
        },
      );
    });
  }
}
