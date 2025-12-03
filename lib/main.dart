import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/routes/app_pages.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart'; // Import AppRoutes
import 'package:ddmco_multimax/app/modules/auth/authentication_controller.dart';
import 'package:ddmco_multimax/app/modules/home/home_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Initialize Services & Global Controllers ---
  await Get.putAsync<ApiProvider>(() async => ApiProvider(), permanent: true);
  Get.put<AuthenticationController>(AuthenticationController(), permanent: true);
  // Removed explicit put of HomeController to avoid dependency issues. 
  // It will be initialized via HomeBinding when needed.

  // --- Determine Initial Route ---
  final authController = Get.find<AuthenticationController>();
  await authController.checkAuthenticationStatus();

  // --- Define Custom Colors ---
  const Color primaryColour = Color(0xFF870E18); // Deep Red
  const Color secondaryColour = Color(0xFF25286F); // Navy Blue
  const Color greyColour = Color(0xFF6F6D6E); // Grey
  const Color backgroundColour = Color(0xFFF5F5F5); // Light Grey Background

  runApp(
    GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KA-ML Fulfillment',
      initialRoute: authController.isAuthenticated.value ? AppRoutes.HOME : AppRoutes.LOGIN,
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
          labelColor: Colors.white, // Active tab text color (on Primary AppBar)
          unselectedLabelColor: Colors.white70, // Inactive tab text color
          indicatorColor: Colors.white, // Underline color
          labelStyle: TextStyle(fontWeight: FontWeight.bold),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: secondaryColour,
          foregroundColor: Colors.white,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: secondaryColour,
          contentTextStyle: TextStyle(color: Colors.white),
          actionTextColor: Colors.white, // Color for "Undo" or other actions
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          surfaceTintColor: Colors.white, // Removes the tint in M3
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: greyColour.withValues(alpha: .2), width: 1),
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
            borderSide: BorderSide(color: greyColour.withValues(alpha: .5)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: secondaryColour,
          ),
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // Ensure typography has good contrast
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: secondaryColour, fontWeight: FontWeight.bold),
          bodyMedium: TextStyle(color: Color(0xFF333333)),
        ),
      ),
      defaultTransition: Transition.fadeIn,
      routingCallback: (routing) {
        if (routing?.current != null) {
          // Safely access HomeController only if registered
          if (Get.isRegistered<HomeController>()) {
            final homeController = Get.find<HomeController>();
            homeController.updateActiveScreen(routing!.current);
          }
        }
      },
    ),
  );
}
