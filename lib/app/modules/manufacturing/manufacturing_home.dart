import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/routes/manufacturing_routes.dart';
import 'package:multimax/app/middleware/permission_middleware.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

/// Manufacturing module home screen with navigation to all manufacturing features
class ManufacturingHome extends StatelessWidget {
  const ManufacturingHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(
        title: 'Manufacturing',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User Role Display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade600, Colors.blue.shade800],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.badge,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Role',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        PermissionHelper.getUserRole(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Navigation Cards
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  // Job Cards (All users)
                  _NavigationCard(
                    icon: Icons.assignment,
                    title: 'Job Cards',
                    subtitle: 'Track operations',
                    color: Colors.blue,
                    onTap: () => Get.toNamed(ManufacturingRoutes.jobCards),
                    enabled: PermissionHelper.canRead('Job Card'),
                  ),

                  // Work Orders (Supervisors and above)
                  _NavigationCard(
                    icon: Icons.factory,
                    title: 'Work Orders',
                    subtitle: 'Manage production',
                    color: Colors.green,
                    onTap: () => Get.toNamed(ManufacturingRoutes.workOrders),
                    enabled: PermissionHelper.canRead('Work Order'),
                  ),

                  // BOM (Supervisors and above)
                  _NavigationCard(
                    icon: Icons.description,
                    title: 'BOM',
                    subtitle: 'Materials & ops',
                    color: Colors.orange,
                    onTap: () => Get.toNamed(ManufacturingRoutes.bom),
                    enabled: PermissionHelper.canRead('BOM'),
                  ),

                  // Reports (Future feature)
                  _NavigationCard(
                    icon: Icons.analytics,
                    title: 'Reports',
                    subtitle: 'Coming soon',
                    color: Colors.purple,
                    onTap: () {},
                    enabled: false,
                  ),
                ],
              ),
            ),

            // Help Section
            if (PermissionHelper.isLabourer()) ..[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.yellow.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.yellow.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.yellow.shade800),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Need help? Ask your supervisor',
                        style: TextStyle(
                          color: Colors.yellow.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavigationCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  const _NavigationCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: enabled ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: enabled
                ? LinearGradient(
                    colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: enabled ? color.withOpacity(0.2) : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 36,
                  color: enabled ? color : Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: enabled ? Colors.black87 : Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: enabled ? Colors.grey[600] : Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
              if (!enabled) ..[
                const SizedBox(height: 8),
                Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: Colors.grey[400],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}