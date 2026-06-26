import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/global_widgets/settings_row.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/session_defaults/session_defaults_controller.dart';

class SessionDefaultsScreen extends GetView<SessionDefaultsController> {
  const SessionDefaultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: 'Session Defaults'),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s4, AppSpace.s2, AppSpace.s4, AppSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroup(
                label: 'Session',
                children: [_companyField(context)],
              ),
              const SizedBox(height: AppSpace.s4),
              SettingsGroup(
                label: 'Automation',
                children: [
                  SettingsSwitchRow(
                    title: 'Auto-submit valid items',
                    subtitle: 'Add item automatically when validation passes',
                    value: controller.autoSubmitEnabled.value,
                    onChanged: (v) => controller.autoSubmitEnabled.value = v,
                  ),
                  if (controller.autoSubmitEnabled.value)
                    SettingsSliderRow(
                      label: 'Auto-submit delay',
                      value: controller.autoSubmitDelay.value,
                      min: 1,
                      max: 10,
                      suffix: 's',
                      help: 'Wait before adding a validated scan to the list',
                      onChanged: (v) => controller.autoSubmitDelay.value = v,
                    ),
                  SettingsSliderRow(
                    label: 'Document save delay',
                    value: controller.autoSaveDelay.value,
                    min: 3,
                    max: 30,
                    suffix: 's',
                    help: 'Wait before saving the document to the server',
                    onChanged: (v) => controller.autoSaveDelay.value = v,
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s4),
              SettingsGroup(
                label: 'Troubleshooting',
                children: [
                  SettingsRow(
                    icon: Icons.sync_lock_outlined,
                    iconTint: AppColors.orange500,
                    title: 'Reload permissions',
                    subtitle: 'Clear cache & re-fetch access rights',
                    onTap: controller.reloadPermissions,
                  ),
                ],
              ),
            ],
          ),
        );
      }),
      bottomNavigationBar: Obx(() => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.s4),
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: controller.isSaving.value ? null : controller.save,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save settings'),
                ),
              ),
            ),
          )),
    );
  }

  Widget _companyField(BuildContext context) {
    final s = context.scheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Company',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: s.textMuted)),
          const SizedBox(height: 7),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => _pickCompany(context),
            child: Container(
              constraints: const BoxConstraints(minHeight: 46),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: s.subtle,
                border: Border.all(color: s.borderStrong),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(Icons.business_outlined, size: 18, color: s.textSubtle),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      controller.selectedCompany.value ?? 'Select company',
                      style: TextStyle(
                          fontSize: 15,
                          color: controller.selectedCompany.value == null
                              ? s.textSubtle
                              : s.text),
                    ),
                  ),
                  Icon(Icons.expand_more, size: 18, color: s.textSubtle),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text('Applied to every new document this session.',
              style: TextStyle(fontSize: 11.5, color: s.textSubtle)),
        ],
      ),
    );
  }

  void _pickCompany(BuildContext context) {
    final s = context.scheme;
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: s.fg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: controller.companies
                .map((name) => ListTile(
                      title: Text(name),
                      trailing: controller.selectedCompany.value == name
                          ? Icon(Icons.check, color: s.primary)
                          : null,
                      onTap: () {
                        controller.selectedCompany.value = name;
                        Get.back();
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}
