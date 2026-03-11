// EXAMPLE: How to integrate manufacturing routes into your main app_pages.dart

import 'package:get/get.dart';
import 'package:multimax/app/routes/manufacturing_routes.dart';
import 'package:multimax/app/modules/manufacturing/manufacturing_home.dart';
import 'package:multimax/app/middleware/permission_middleware.dart';

// This is an EXAMPLE file showing how to add manufacturing routes
// Copy the relevant sections to your actual app_pages.dart

class AppPages {
  AppPages._();

  static const INITIAL = '/home';

  static final routes = [
    // ==========================================
    // EXISTING ROUTES (your app's routes)
    // ==========================================
    GetPage(
      name: '/home',
      page: () => const HomePage(),
    ),
    GetPage(
      name: '/login',
      page: () => const LoginPage(),
    ),
    // ... your other routes ...

    // ==========================================
    // MANUFACTURING MODULE ROUTES (ADD THESE)
    // ==========================================
    
    // Manufacturing Home Screen
    GetPage(
      name: '/manufacturing',
      page: () => const ManufacturingHome(),
      middlewares: [
        PermissionMiddleware(
          requiredPermissions: ['Manufacturing', 'read'],
          roles: [
            'Manufacturing Manager',
            'Manufacturing User',
            'Supervisor',
            'Labourer',
          ],
        ),
      ],
    ),

    // All Manufacturing Sub-Routes (BOM, Work Order, Job Card)
    ...ManufacturingRoutes.routes,
  ];
}

// Dummy classes for example (remove these, use your actual pages)
class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => Container();
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) => Container();
}