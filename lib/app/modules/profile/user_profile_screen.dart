import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/profile/user_profile_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class UserProfileScreen extends GetView<UserProfileController> {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
          return const Center(child: Text('User data not available'));
        }

        final theme       = Theme.of(context);
        final primary     = theme.primaryColor;
        final hasImage    = user.image != null && user.image!.isNotEmpty;
        final initials    = user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U';
        final subtitle    = [
          if (user.designation != null && user.designation!.isNotEmpty) user.designation!,
          if (user.department  != null && user.department!.isNotEmpty)  user.department!,
        ].join(' · ');

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // ── Hero header ────────────────────────────────────────────
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: primary, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: primary.withValues(alpha: 0.1),
                    backgroundImage:
                        hasImage ? NetworkImage(user.image!) : null,
                    child: hasImage
                        ? null
                        : Text(
                            initials,
                            style: TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: primary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  user.name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style:
                      const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500),
                  ),
                ],
                const SizedBox(height: 32),

                // ── General Information ────────────────────────────────────
                _buildSectionTitle('General Information'),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Email (replaces redundant User ID row)
                        _buildInfoRow(
                          'Email',
                          user.email,
                          icon: Icons.email_outlined,
                        ),
                        const Divider(height: 24),
                        _buildInfoRow(
                          'Designation',
                          user.designation?.isNotEmpty == true
                              ? user.designation!
                              : null,
                          icon: Icons.badge_outlined,
                        ),
                        const Divider(height: 24),
                        _buildInfoRow(
                          'Department',
                          user.department?.isNotEmpty == true
                              ? user.department!
                              : null,
                          icon: Icons.business_outlined,
                        ),
                        const Divider(height: 24),
                        _buildEditableRow(
                          context,
                          'Mobile',
                          user.mobileNo?.isNotEmpty == true
                              ? user.mobileNo!
                              : null,
                          Icons.phone_android,
                          () => _showUpdateMobileDialog(
                              context, user.mobileNo),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Assigned Roles ─────────────────────────────────────────
                if (user.roles.isNotEmpty) ...[
                  _buildSectionTitle('Assigned Roles'),
                  const SizedBox(height: 12),
                  _buildRoleChips(context, user.roles),
                  const SizedBox(height: 32),
                ],

                // ── Account Settings ───────────────────────────────────────
                _buildSectionTitle('Account Settings'),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.lock_outline,
                            color: Colors.blueGrey),
                        title: const Text('Change Password'),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.grey),
                        onTap: () => _showChangePasswordSheet(context),
                      ),
                      Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: Colors.grey.shade200),
                      // Logout — confirmation required
                      ListTile(
                        leading:
                            const Icon(Icons.logout, color: Colors.red),
                        title: const Text('Logout',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right,
                            color: Colors.red),
                        onTap: () => GlobalDialog.showConfirmation(
                          title: 'Log Out?',
                          message:
                              'Are you sure you want to log out of your account?',
                          confirmText: 'Log Out',
                          confirmColor: Colors.red,
                          icon: Icons.logout,
                          onConfirm: controller.logout,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ── Role chips ─────────────────────────────────────────────────────────────
  // A flat list of roles has no hierarchy — Wrap of chips is more scannable
  // and less misleading than the previous tree-connector pattern.
  Widget _buildRoleChips(BuildContext context, List<String> roles) {
    final sorted = List<String>.from(roles)..sort();
    final primary = Theme.of(context).primaryColor;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: sorted.map((role) {
            return Chip(
              avatar: Icon(Icons.verified_user_outlined,
                  size: 15, color: primary),
              label: Text(role,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              backgroundColor: primary.withValues(alpha: 0.06),
              side: BorderSide(color: primary.withValues(alpha: 0.25)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 4, vertical: 0),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87),
      ),
    );
  }

  /// Pass [value] as null to render an em-dash placeholder instead of
  /// the previous 'Not Set' string, which read as an error state.
  Widget _buildInfoRow(String label, String? value, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                value ?? '\u2014', // em-dash for empty optional fields
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: value != null ? Colors.black87 : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditableRow(
    BuildContext context,
    String label,
    String? value,
    IconData icon,
    VoidCallback onEdit,
  ) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                value ?? '\u2014',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: value != null ? Colors.black87 : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.edit, size: 20, color: Colors.blue),
          onPressed: onEdit,
        ),
      ],
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────────────

  void _showUpdateMobileDialog(
      BuildContext context, String? currentMobile) {
    final mobileController =
        TextEditingController(text: currentMobile);
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
          TextButton(
              onPressed: () => Get.back(),
              child: const Text('Cancel')),
          Obx(() => ElevatedButton(
                onPressed: controller.isUpdating.value
                    ? null
                    : () {
                        if (formKey.currentState!.validate()) {
                          controller.updateMobileNumber(
                              mobileController.text);
                        }
                      },
                child: controller.isUpdating.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                    : const Text('Update'),
              )),
        ],
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context) {
    final oldPassController     = TextEditingController();
    final newPassController     = TextEditingController();
    final confirmPassController = TextEditingController();
    final formKey               = GlobalKey<FormState>();

    final RxBool obscureOld     = true.obs;
    final RxBool obscureNew     = true.obs;
    final RxBool obscureConfirm = true.obs;

    Get.bottomSheet(
      // Keyboard inset at the outermost level so the submit button
      // is never buried under the soft keyboard.
      Obx(() => Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
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
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Change Password',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge),
                            IconButton(
                                onPressed: () => Get.back(),
                                icon: const Icon(Icons.close)),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Current Password
                        TextFormField(
                          controller: oldPassController,
                          obscureText: obscureOld.value,
                          decoration: InputDecoration(
                            labelText: 'Current Password',
                            prefixIcon:
                                const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(obscureOld.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => obscureOld.toggle(),
                            ),
                          ),
                          validator: (val) => val == null || val.isEmpty
                              ? 'Required'
                              : null,
                        ),
                        const SizedBox(height: 16),

                        // New Password
                        TextFormField(
                          controller: newPassController,
                          obscureText: obscureNew.value,
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            prefixIcon:
                                const Icon(Icons.vpn_key_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(obscureNew.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => obscureNew.toggle(),
                            ),
                          ),
                          validator: (val) =>
                              val == null || val.length < 6
                                  ? 'Minimum 6 characters required'
                                  : null,
                        ),
                        const SizedBox(height: 16),

                        // Confirm Password
                        TextFormField(
                          controller: confirmPassController,
                          obscureText: obscureConfirm.value,
                          decoration: InputDecoration(
                            labelText: 'Confirm New Password',
                            prefixIcon: const Icon(
                                Icons.check_circle_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(obscureConfirm.value
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () =>
                                  obscureConfirm.toggle(),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty)
                              return 'Required';
                            if (val != newPassController.text)
                              return 'Passwords do not match';
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
                                        if (formKey.currentState!
                                            .validate()) {
                                          controller.changePassword(
                                            oldPassController.text,
                                            newPassController.text,
                                          );
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                                child: controller.isUpdating.value
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ))
                                    : const Text('Update Password',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight:
                                                FontWeight.bold)),
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

// ── Shimmer skeleton ──────────────────────────────────────────────────────────
// Shown while controller.isLoading == true so the user has immediate spatial
// context instead of a blank white screen with a centered spinner.
class _ProfileSkeleton extends StatefulWidget {
  const _ProfileSkeleton();

  @override
  State<_ProfileSkeleton> createState() => _ProfileSkeletonState();
}

class _ProfileSkeletonState extends State<_ProfileSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Color?> _color;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _color = ColorTween(
      begin: Colors.grey.shade100,
      end: Colors.grey.shade300,
    ).animate(_anim);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _box({double w = double.infinity, double h = 14, double r = 8}) {
    return AnimatedBuilder(
      animation: _color,
      builder: (_, __) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: _color.value,
          borderRadius: BorderRadius.circular(r),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            // Avatar circle
            AnimatedBuilder(
              animation: _color,
              builder: (_, __) => CircleAvatar(
                radius: 56,
                backgroundColor: _color.value,
              ),
            ),
            const SizedBox(height: 14),
            // Name line
            _box(w: 160, h: 18),
            const SizedBox(height: 8),
            // Email line
            _box(w: 220, h: 13),
            const SizedBox(height: 4),
            // Subtitle line
            _box(w: 140, h: 13),
            const SizedBox(height: 32),
            // Card skeleton
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: List.generate(3, (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      _box(w: 20, h: 20, r: 4),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _box(w: 80, h: 11),
                            const SizedBox(height: 6),
                            _box(h: 14),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
