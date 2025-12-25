import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/about/about_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

class AboutScreen extends GetView<AboutController> {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const MainAppBar(title: 'System Information'),
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: controller.runHealthChecks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              _buildAppHeader(theme),
              const SizedBox(height: 32),
              _buildVersionCard(theme),
              const SizedBox(height: 24),
              _buildSystemHealthSection(theme),
              const SizedBox(height: 48),
              _buildFooter(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppHeader(ThemeData theme) {
    return Column(
      children: [
        Hero(
          tag: 'app_logo',
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
              image: const DecorationImage(image: AssetImage('lib/assets/images/logo.jpg')),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Obx(() => Text(
          controller.appName.value.isEmpty ? 'ERP' : controller.appName.value,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.primaryColor),
        )),
      ],
    );
  }

  Widget _buildVersionCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Obx(() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildVersionItem(theme, 'Version', controller.version.value),
          Container(height: 30, width: 1, color: Colors.grey.shade300),
          _buildVersionItem(theme, 'Build', controller.buildNumber.value),
        ],
      )),
    );
  }

  Widget _buildVersionItem(ThemeData theme, String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildSystemHealthSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('System Health', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Obx(() => controller.isCheckingHealth.value
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const SizedBox.shrink()),
            ],
          ),
        ),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
          child: Obx(() => Column(
            children: controller.systemStatus.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == controller.systemStatus.length - 1;
              return Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: _buildStatusIcon(item.state),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.type, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        if (item.filePath != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              item.filePath!,
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontFamily: 'monospace'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          item.details ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _getStatusColor(item.state),
                          ),
                        ),
                        if (item.latency != null)
                          Text(
                            item.latency!,
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  if (!isLast) const Divider(height: 1, indent: 56),
                ],
              );
            }).toList(),
          )),
        ),
      ],
    );
  }

  Widget _buildStatusIcon(IntegrationState state) {
    switch (state) {
      case IntegrationState.loading:
        return Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
          child: const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)),
        );
      case IntegrationState.connected:
        return Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
          child: Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 20),
        );
      case IntegrationState.error:
      case IntegrationState.offline:
        return Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
          child: Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
        );
    }
  }

  Color _getStatusColor(IntegrationState state) {
    switch (state) {
      case IntegrationState.connected: return Colors.green.shade700;
      case IntegrationState.error:
      case IntegrationState.offline: return Colors.red.shade700;
      default: return Colors.grey;
    }
  }

  Widget _buildFooter(ThemeData theme) {
    return Center(
      child: Text(
        '© ${DateTime.now().year} ERP\nPowered by DDMCO',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade400),
      ),
    );
  }
}