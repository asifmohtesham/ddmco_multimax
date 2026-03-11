import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/routes/app_pages.dart';

/// Manufacturing menu section for home/navigation drawer
/// Add this to your existing navigation menu
class ManufacturingMenuSection extends StatelessWidget {
  const ManufacturingMenuSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'MANUFACTURING',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
              letterSpacing: 1.2,
            ),
          ),
        ),
        _ManufacturingMenuItem(
          icon: Icons.inventory_2,
          title: 'Bill of Materials',
          subtitle: 'View BOMs',
          color: Colors.blue,
          onTap: () => Get.toNamed(Routes.MANUFACTURING_BOM),
        ),
        _ManufacturingMenuItem(
          icon: Icons.factory,
          title: 'Work Orders',
          subtitle: 'Track production',
          color: Colors.green,
          onTap: () => Get.toNamed(Routes.MANUFACTURING_WORK_ORDERS),
        ),
        _ManufacturingMenuItem(
          icon: Icons.assignment,
          title: 'Job Cards',
          subtitle: 'Operations tracking',
          color: Colors.orange,
          onTap: () => Get.toNamed(Routes.MANUFACTURING_JOB_CARDS),
        ),
        const Divider(height: 24),
      ],
    );
  }
}

class _ManufacturingMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ManufacturingMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Colors.grey[600],
        ),
      ),
      trailing: Icon(Icons.chevron_right, color: Colors.grey[400]),
      onTap: onTap,
    );
  }
}

/// Alternative: Dashboard Cards for home screen
class ManufacturingDashboardCards extends StatelessWidget {
  const ManufacturingDashboardCards({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _DashboardCard(
                icon: Icons.factory,
                title: 'Work Orders',
                count: '12',
                color: Colors.green,
                onTap: () => Get.toNamed(Routes.MANUFACTURING_WORK_ORDERS),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DashboardCard(
                icon: Icons.assignment,
                title: 'Job Cards',
                count: '28',
                color: Colors.orange,
                onTap: () => Get.toNamed(Routes.MANUFACTURING_JOB_CARDS),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DashboardCard(
          icon: Icons.inventory_2,
          title: 'Bill of Materials',
          count: '45 BOMs',
          color: Colors.blue,
          fullWidth: true,
          onTap: () => Get.toNamed(Routes.MANUFACTURING_BOM),
        ),
      ],
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String count;
  final Color color;
  final bool fullWidth;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
    this.fullWidth = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withOpacity(0.8), color],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 36),
              const SizedBox(height: 12),
              Text(
                count,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}