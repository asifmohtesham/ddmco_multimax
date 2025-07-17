import 'package:ddmco_multimax/app/data/providers/api_provider.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/providers/api_provider.dart'; // Update path
import 'package:ddmco_multimax/app/data/routes/app_pages.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart'; // Import AppRoutes
// Import the new AuthenticationController
import 'package:ddmco_multimax/app/modules/auth/authentication_controller.dart';
// Optional: import 'package:your_app_name/app/services/storage_service.dart';
// Optional: import 'package:get_storage/get_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --- Initialize Services & Global Controllers ---

  // Optional: Initialize GetStorage if using StorageService
  // await GetStorage.init();
  // Get.put<StorageService>(StorageService(), permanent: true);

  // Initialize ApiProvider first as AuthenticationController depends on it
  await Get.putAsync<ApiProvider>(() async => ApiProvider(), permanent: true);

  // Initialize AuthenticationController globally and make it permanent
  Get.put<AuthenticationController>(AuthenticationController(), permanent: true);


  // --- Determine Initial Route ---
  // The AuthenticationController's onInit will call checkAuthenticationStatus.
  // We can observe its state to decide the initial route.
  final authController = Get.find<AuthenticationController>();

  // It's better to wait for checkAuthenticationStatus to complete
  // or show a splash screen while it's loading.
  // For simplicity, we'll use a FutureBuilder or an observer in a splash screen.
  // Here's a simplified way assuming onInit runs quickly enough for this example:
  // (A Splash screen approach is more robust for production)

  // Wait for the initial check to potentially complete if it's quick
  // A more robust way is to have a dedicated Splash/Loading screen that observes authController.isLoading
  await authController.checkAuthenticationStatus(); // Ensure this is awaited or handled with a loading screen

  runApp(
    GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Your App Name',
      // initialRoute is determined by observing isAuthenticated in a Root/Splash widget
      // For now, let's keep the logic from before, but ideally, this moves to a wrapper widget.
      initialRoute: authController.isAuthenticated.value ? AppRoutes.HOME : AppRoutes.LOGIN,
      getPages: AppPages.routes,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      defaultTransition: Transition.fadeIn,
    ),
  );}
