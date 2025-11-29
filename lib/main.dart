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
  Get.put<HomeController>(HomeController(), permanent: true);

  // --- Determine Initial Route ---
  final authController = Get.find<AuthenticationController>();
  await authController.checkAuthenticationStatus();

  runApp(
    GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KA-ML Fulfillment',
      initialRoute: authController.isAuthenticated.value ? AppRoutes.HOME : AppRoutes.LOGIN,
      getPages: AppPages.routes,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      defaultTransition: Transition.fadeIn,
      routingCallback: (routing) {
        if (routing?.current != null) {
          final homeController = Get.find<HomeController>();
          homeController.updateActiveScreen(routing!.current);
        }
      },
    ),
  );
}
