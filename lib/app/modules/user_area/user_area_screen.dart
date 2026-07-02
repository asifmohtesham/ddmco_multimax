import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/global_widgets/settings_row.dart';
import 'package:multimax/app/modules/user_area/user_area_controller.dart';

class UserAreaScreen extends GetView<UserAreaController> {
  const UserAreaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: 'Account'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.s4, AppSpace.s3, AppSpace.s4, AppSpace.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Obx(() => _ProfileCard(user: controller.user.value)),
            const SizedBox(height: AppSpace.s5),
            SettingsGroup(
              label: 'Preferences',
              children: [
                Obx(() => SettingsRow(
                      icon: Icons.palette_outlined,
                      iconTint: AppColors.purple500,
                      title: 'Theme',
                      value: controller.themeModeLabel,
                      onTap: () => Get.toNamed(AppRoutes.THEME),
                    )),
                SettingsRow(
                  icon: Icons.tune,
                  iconTint: AppColors.cyan500,
                  title: 'Session Defaults',
                  value: controller.company,
                  onTap: () => Get.toNamed(AppRoutes.SESSION_DEFAULTS),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            SettingsGroup(
              label: 'Support',
              children: [
                Obx(() => SettingsRow(
                      icon: Icons.info_outline,
                      iconTint: AppColors.blue500,
                      title: 'System Information',
                      value: controller.version.value.isEmpty
                          ? null
                          : 'v${controller.version.value}',
                      onTap: () => Get.toNamed(AppRoutes.ABOUT),
                    )),
              ],
            ),
            const SizedBox(height: AppSpace.s6),
            _LogoutButton(onTap: controller.logout),
            const SizedBox(height: AppSpace.s4),
            Obx(() => _Footer(
                  email: controller.user.value?.email ?? '',
                  version: controller.version.value,
                  buildNumber: controller.build.value,
                )),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final User? user;
  const _ProfileCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final name = user?.name ?? 'Guest';
    final email = user?.email ?? '';
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    final roleDept = [
      if ((user?.designation ?? '').isNotEmpty) user!.designation!,
      if ((user?.department ?? '').isNotEmpty) user!.department!,
    ].join(' · ');

    return Material(
      color: s.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: () => Get.toNamed(AppRoutes.PROFILE),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.s4),
          decoration: BoxDecoration(
            border: Border.all(color: s.border),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Row(
            children: [
              AppAvatar(size: 56, initials: initials),
              const SizedBox(width: AppSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: s.text)),
                    if (email.isNotEmpty)
                      Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: s.textMuted)),
                    if (roleDept.isNotEmpty)
                      Text(roleDept,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: s.textMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: s.textSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final red = isDark ? AppColors.red300 : AppColors.red700;
    return Material(
      color: Color.alphaBlend(AppColors.red500.withValues(alpha: 0.10), s.fg),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
                color: Color.alphaBlend(
                    AppColors.red500.withValues(alpha: 0.26), s.border)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.logout, size: 19, color: red),
              const SizedBox(width: 9),
              Text('Log out',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: red)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final String email;
  final String version;
  final String buildNumber;
  const _Footer(
      {required this.email, required this.version, required this.buildNumber});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final ver = version.isEmpty ? '' : 'Multimax v$version · build $buildNumber';
    return Column(
      children: [
        if (email.isNotEmpty)
          Text('Signed in as $email',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: s.textMuted)),
        if (ver.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(ver,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: s.textMuted)),
          ),
      ],
    );
  }
}
