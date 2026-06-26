import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/modules/global_widgets/app_avatar.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/global_widgets/settings_row.dart';
import 'package:multimax/app/modules/global_widgets/skeleton_box.dart';
import 'package:multimax/app/modules/profile/user_profile_controller.dart';

class UserProfileScreen extends GetView<UserProfileController> {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Scaffold(
      appBar: MainAppBar(
        title: 'My Profile',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.refreshProfile,
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const _ProfileSkeleton();
        }

        final user = controller.user.value;
        if (user == null) {
          return Center(
            child: Text('User data not available',
                style: TextStyle(color: s.textMuted)),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s4, AppSpace.s2, AppSpace.s4, AppSpace.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _hero(context, user),
              const SizedBox(height: AppSpace.s5),

              // ── General information ────────────────────────────────────
              SettingsGroup(
                label: 'General information',
                children: [
                  _KvRow(
                      icon: Icons.badge_outlined,
                      label: 'Employee ID',
                      value: user.employeeId),
                  _KvRow(
                      icon: Icons.apartment_outlined,
                      label: 'Department',
                      value: user.department),
                  _KvRow(
                      icon: Icons.work_outline,
                      label: 'Designation',
                      value: user.designation),
                  _KvRow(
                    icon: Icons.phone_android,
                    label: 'Mobile',
                    value: user.mobileNo,
                    onEdit: () => _showUpdateMobileDialog(context, user.mobileNo),
                  ),
                ],
              ),

              // ── Roles ──────────────────────────────────────────────────
              if (user.roles.isNotEmpty) ...[
                const SizedBox(height: AppSpace.s4),
                SettingsGroup(
                  label: 'Roles · ${user.roles.length}',
                  children: [_RoleChips(roles: user.roles)],
                ),
              ],

              // ── Security ───────────────────────────────────────────────
              // Logout intentionally lives only in the Account hub now
              // (single, confirmed exit point).
              const SizedBox(height: AppSpace.s4),
              SettingsGroup(
                label: 'Security',
                children: [
                  SettingsRow(
                    icon: Icons.lock_outline,
                    iconTint: s.textMuted,
                    title: 'Change password',
                    onTap: () => _showChangePasswordSheet(context),
                  ),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _hero(BuildContext context, User user) {
    final s = context.scheme;
    final hasImage = user.image != null && user.image!.isNotEmpty;
    final initials = user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U';
    final subtitle = [
      if (user.designation?.isNotEmpty == true) user.designation!,
      if (user.department?.isNotEmpty == true) user.department!,
    ].join(' · ');

    return Column(
      children: [
        AppAvatar(
          size: 92,
          initials: initials,
          image: hasImage ? NetworkImage(user.image!) : null,
        ),
        const SizedBox(height: 12),
        Text(user.name,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: s.text)),
        const SizedBox(height: 3),
        Text(user.email,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: s.textMuted)),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: s.textSubtle)),
        ],
      ],
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showUpdateMobileDialog(BuildContext context, String? currentMobile) {
    final mobileController = TextEditingController(text: currentMobile);
    final formKey = GlobalKey<FormState>();

    Get.dialog(
      AlertDialog(
        title: const Text('Update Mobile Number'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: mobileController,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  hintText: '+971... or +91...',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: controller.validateMobileNumber,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          Obx(() => ElevatedButton(
                onPressed: controller.isUpdating.value
                    ? null
                    : () {
                        if (formKey.currentState!.validate()) {
                          controller.updateMobileNumber(mobileController.text);
                        }
                      },
                child: controller.isUpdating.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Update'),
              )),
        ],
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context) {
    final s = context.scheme;
    final oldPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final RxBool obscureOld = true.obs;
    final RxBool obscureNew = true.obs;
    final RxBool obscureConfirm = true.obs;

    Get.bottomSheet(
      Obx(() => Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: s.fg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Change Password',
                                style: Theme.of(context).textTheme.titleLarge),
                            IconButton(
                                onPressed: () => Get.back(),
                                icon: const Icon(Icons.close)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: oldPassController,
                          obscureText: obscureOld.value,
                          decoration: InputDecoration(
                            labelText: 'Current Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(obscureOld.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => obscureOld.toggle(),
                            ),
                          ),
                          validator: (val) =>
                              val == null || val.isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: newPassController,
                          obscureText: obscureNew.value,
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            prefixIcon: const Icon(Icons.vpn_key_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(obscureNew.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => obscureNew.toggle(),
                            ),
                          ),
                          validator: (val) => val == null || val.length < 6
                              ? 'Minimum 6 characters required'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: confirmPassController,
                          obscureText: obscureConfirm.value,
                          decoration: InputDecoration(
                            labelText: 'Confirm New Password',
                            prefixIcon: const Icon(Icons.check_circle_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(obscureConfirm.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => obscureConfirm.toggle(),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Required';
                            if (val != newPassController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: Obx(() => ElevatedButton(
                                onPressed: controller.isUpdating.value
                                    ? null
                                    : () {
                                        if (formKey.currentState!.validate()) {
                                          controller.changePassword(
                                            oldPassController.text,
                                            newPassController.text,
                                          );
                                        }
                                      },
                                child: controller.isUpdating.value
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.5))
                                    : const Text('Update Password',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold)),
                              )),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )),
      isScrollControlled: true,
    );
  }
}

/// Key/value row (the design's `.ua-kv`): leading icon, small label over value,
/// optional edit affordance. Theme-aware via [BuildContext.scheme].
class _KvRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onEdit;
  const _KvRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final has = value != null && value!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 19, color: s.textSubtle),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: s.textSubtle)),
                const SizedBox(height: 2),
                Text(has ? value! : '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: has ? s.text : s.textSubtle)),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              icon: Icon(Icons.edit, size: 18, color: s.primary),
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

/// Wrap of primary-tinted role chips (the design's `.ua-chip`).
class _RoleChips extends StatelessWidget {
  final List<String> roles;
  const _RoleChips({required this.roles});

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final sorted = List<String>.from(roles)..sort();
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final role in sorted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Color.alphaBlend(s.primary.withValues(alpha: 0.09), s.fg),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                    color:
                        Color.alphaBlend(s.primary.withValues(alpha: 0.26), s.border)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_outlined, size: 14, color: s.primary),
                  const SizedBox(width: 6),
                  Text(role,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: s.primary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Theme-aware loading placeholder shown while the profile is fetching.
class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.s4, AppSpace.s4, AppSpace.s4, AppSpace.s8),
      child: Column(
        children: [
          const SkeletonBox(width: 92, height: 92, radius: 46),
          const SizedBox(height: 14),
          const SkeletonBox(width: 160, height: 18),
          const SizedBox(height: 8),
          const SkeletonBox(width: 220, height: 13),
          const SizedBox(height: AppSpace.s5),
          Container(
            decoration: BoxDecoration(
              color: s.fg,
              border: Border.all(color: s.border),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(
                4,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      const SkeletonBox(width: 20, height: 20, radius: 4),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            SkeletonBox(width: 80, height: 11),
                            SizedBox(height: 6),
                            SkeletonBox(height: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
