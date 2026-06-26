import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/about/about_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';

class AboutScreen extends GetView<AboutController> {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Scaffold(
      appBar: MainAppBar(
        title: 'System Information',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.runHealthChecks,
          ),
        ],
      ),
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: controller.runHealthChecks,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s4, AppSpace.s4, AppSpace.s4, AppSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context),
              const SizedBox(height: AppSpace.s5),
              _versionCard(context),
              const SizedBox(height: AppSpace.s5),
              const SectionLabel(text: 'System health'),
              _healthCard(context),
              const SizedBox(height: AppSpace.s8),
              Center(
                child: Text(
                  '© ${DateTime.now().year} Multimax · Powered by DDMCO',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: s.textSubtle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final s = context.scheme;
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            image: const DecorationImage(
              image: AssetImage('lib/assets/images/logo.jpg'),
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Obx(() => Text(
              controller.appName.value.isEmpty
                  ? 'Multimax'
                  : controller.appName.value,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: s.text),
            )),
      ],
    );
  }

  Widget _versionCard(BuildContext context) {
    final s = context.scheme;
    Widget cell(String k, String v) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              children: [
                Text(k,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: s.textSubtle)),
                const SizedBox(height: 3),
                Text(v,
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: s.text)),
              ],
            ),
          ),
        );
    Widget sep() => Container(width: 1, height: 36, color: s.border);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.fg,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Obx(() => IntrinsicHeight(
            child: Row(
              children: [
                cell(
                    'Version',
                    controller.version.value.isEmpty
                        ? '—'
                        : controller.version.value),
                sep(),
                cell(
                    'Build',
                    controller.buildNumber.value.isEmpty
                        ? '—'
                        : controller.buildNumber.value),
                sep(),
                cell('Channel', controller.channel),
              ],
            ),
          )),
    );
  }

  Widget _healthCard(BuildContext context) {
    final s = context.scheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.fg,
        border: Border.all(color: s.border),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Obx(() {
          final items = controller.systemStatus;
          final rows = <Widget>[];
          for (var i = 0; i < items.length; i++) {
            if (i > 0) {
              rows.add(Divider(height: 1, thickness: 1, color: s.border));
            }
            rows.add(_healthRow(context, items[i]));
          }
          return Column(mainAxisSize: MainAxisSize.min, children: rows);
        }),
      ),
    );
  }

  Widget _healthRow(BuildContext context, SystemIntegration item) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = item.state == IntegrationState.connected;
    final loading = item.state == IntegrationState.loading;
    final tint = ok ? AppColors.green500 : AppColors.red500;
    final detailColor = ok
        ? (isDark ? AppColors.green300 : AppColors.green700)
        : (isDark ? AppColors.red300 : AppColors.red700);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Color.alphaBlend(tint.withValues(alpha: 0.14), s.fg),
              shape: BoxShape.circle,
            ),
            child: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(ok ? Icons.check_rounded : Icons.error_outline,
                    size: 19, color: detailColor),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.name,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: s.text)),
                Text(item.type,
                    style: TextStyle(fontSize: 11.5, color: s.textSubtle)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.details != null && !loading)
                Text(item.details!,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: detailColor)),
              if (item.latency != null)
                Text(item.latency!,
                    style: TextStyle(fontSize: 10.5, color: s.textSubtle)),
            ],
          ),
        ],
      ),
    );
  }
}
