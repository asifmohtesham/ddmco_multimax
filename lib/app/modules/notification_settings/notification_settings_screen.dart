import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/services/digest_service.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/notification_settings/notification_settings_controller.dart';

class NotificationSettingsScreen
    extends GetView<NotificationSettingsController> {
  const NotificationSettingsScreen({super.key});

  static const _dayLabels = {
    DateTime.monday: 'Mon',
    DateTime.tuesday: 'Tue',
    DateTime.wednesday: 'Wed',
    DateTime.thursday: 'Thu',
    DateTime.friday: 'Fri',
    DateTime.saturday: 'Sat',
    DateTime.sunday: 'Sun',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar(title: 'Notifications'),
      body: Obx(
        () => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s4, AppSpace.s2, AppSpace.s4, AppSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsGroup(
                children: [
                  SettingsSwitchRow(
                    title: 'Scheduled digest',
                    subtitle:
                        'Notify me about documents that need action, even '
                        'when the app is closed',
                    value: controller.enabled.value,
                    onChanged: controller.setEnabled,
                  ),
                ],
              ),
              if (controller.enabled.value) ...[
                const SizedBox(height: AppSpace.s4),
                SettingsGroup(
                  label: 'Times',
                  children: [_timesEditor(context)],
                ),
                const SizedBox(height: AppSpace.s4),
                SettingsGroup(
                  label: 'Days',
                  children: [_daysEditor()],
                ),
                const SizedBox(height: AppSpace.s4),
                SettingsGroup(
                  label: 'Alert style',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.s3),
                      child: SettingsSegmented<String>(
                        value: controller.alarmStyle.value,
                        onChanged: controller.setAlarmStyle,
                        options: const [
                          SegmentOption(
                              value: 'standard',
                              label: 'Standard',
                              icon: Icons.notifications_active_outlined),
                          SegmentOption(
                              value: 'alarm',
                              label: 'Alarm',
                              icon: Icons.alarm),
                        ],
                      ),
                    ),
                  ],
                ),
                // iOS reminders are generic text (no per-doctype counts), so
                // the Documents selector only applies on Android.
                if (!kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.android) ...[
                  const SizedBox(height: AppSpace.s4),
                  SettingsGroup(
                    label: 'Documents',
                    children: [
                      for (final d in kDigestDoctypes)
                        SettingsSwitchRow(
                          title: d.doctype,
                          value: controller.doctypeKeys.contains(d.key),
                          onChanged: (_) => controller.toggleDoctype(d.key),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _timesEditor(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s3),
      child: Wrap(
        spacing: AppSpace.s2,
        runSpacing: AppSpace.s2,
        children: [
          for (final t in controller.times)
            InputChip(
              label: Text(t),
              onDeleted: () => controller.removeTime(t),
            ),
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Add time'),
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 9, minute: 0),
              );
              if (picked != null) {
                controller.addTime(picked.hour, picked.minute);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _daysEditor() {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s3),
      child: Wrap(
        spacing: AppSpace.s2,
        runSpacing: AppSpace.s2,
        children: [
          for (final entry in _dayLabels.entries)
            SelectableFilterChip(
              label: entry.value,
              selected: controller.days.contains(entry.key),
              onSelected: (_) => controller.toggleDay(entry.key),
            ),
        ],
      ),
    );
  }
}
