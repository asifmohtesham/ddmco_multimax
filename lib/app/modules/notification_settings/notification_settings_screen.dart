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
      body: Obx(() {
        // Read unconditionally so every build path — including "neither
        // manager nor linked employee", where every branch below is gated
        // off — still reads at least one Rx. An Obx that reads zero
        // observables throws in GetX 4.7.2 (the same crash class as the PO
        // list FAB fix).
        final blocked = controller.notificationsBlocked.value;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s4, AppSpace.s2, AppSpace.s4, AppSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (controller.showAttendance || controller.showTerminal) ...[
                SettingsGroup(
                  label: 'Attendance',
                  children: [
                    if (controller.showAttendance)
                      SettingsSwitchRow(
                        title: 'Attendance reminders',
                        subtitle: 'Check-in and check-out reminders for your shifts, '
                            'and a morning recap when something was missed',
                        value: controller.attendanceEnabled.value,
                        onChanged: controller.setAttendanceEnabled,
                      ),
                    if (controller.showTerminal)
                      SettingsSwitchRow(
                        title: 'Terminal alerts',
                        subtitle: 'Tell me when the attendance terminal or its sync goes quiet',
                        value: controller.terminalEnabled.value,
                        onChanged: controller.setTerminalEnabled,
                      ),
                  ],
                ),
                if (blocked)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.s3, AppSpace.s2, AppSpace.s3, 0),
                    child: Text(
                      'Notifications are turned off for Multimax. Allow them in Android settings '
                      'to get these reminders.',
                      style: TextStyle(fontSize: 12.5, color: context.scheme.textMuted),
                    ),
                  ),
                const SizedBox(height: AppSpace.s4),
              ],
              if (controller.showDigest) ...[
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
            ],
          ),
        );
      }),
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
