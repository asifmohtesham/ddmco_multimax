import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/profile/user_profile_controller.dart';

class UserProfileScreen extends GetView<UserProfileController> {
  const UserProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: controller.refreshProfile,
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        final user = controller.user.value;
        if (user == null) {
          return const Center(child: Text('User data not available'));
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                // Profile Avatar
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  child: Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  user.name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  user.email,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 32),

                // Details Section
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
                        _buildInfoRow('User ID', user.id, icon: Icons.fingerprint),
                        const Divider(height: 24),
                        _buildInfoRow('Designation', user.designation ?? 'Not Set', icon: Icons.badge_outlined),
                        const Divider(height: 24),
                        _buildInfoRow('Department', user.department ?? 'Not Set', icon: Icons.business_outlined),
                        const Divider(height: 24),
                        _buildEditableRow(context, 'Mobile', user.mobileNo ?? 'Not Set', Icons.phone_android, () => _showUpdateMobileDialog(context, user.mobileNo)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Roles Section (Tree View)
                if (user.roles.isNotEmpty) ...[
                  _buildSectionTitle('Assigned Roles'),
                  const SizedBox(height: 12),
                  _buildRoleTree(context, user.roles),
                  const SizedBox(height: 32),
                ],

                // Actions Section
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
                        leading: const Icon(Icons.lock_outline, color: Colors.blueGrey),
                        title: const Text('Change Password'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showChangePasswordSheet(context),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: controller.logout,
                    icon: const Icon(Icons.logout, color: Colors.red),
                    label: const Text('Logout', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
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

  // --- Tree View Builders ---

  Widget _buildRoleTree(BuildContext context, List<String> roles) {
    final sortedRoles = List<String>.from(roles)..sort();
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
        child: Column(
          children: sortedRoles.asMap().entries.map((entry) {
            return _buildRoleNode(
                context,
                entry.value,
                entry.key == 0,
                entry.key == sortedRoles.length - 1
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRoleNode(BuildContext context, String role, bool isFirst, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tree Connector Column
          Column(
            children: [
              // Top Line
              Container(
                width: 2,
                height: 18, // Distance to center of node
                color: isFirst ? Colors.transparent : Colors.grey.shade300,
              ),
              // Node Circle
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).primaryColor,
                      width: 2.5
                  ),
                ),
              ),
              // Bottom Line
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast ? Colors.transparent : Colors.grey.shade300,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Role Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified_user_outlined, size: 18, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        role,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Dialogs & Helpers ---

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
            onPressed: controller.isUpdating.value ? null : () {
              if (formKey.currentState!.validate()) {
                controller.updateMobileNumber(mobileController.text);
              }
            },
            child: controller.isUpdating.value
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Update'),
          )),
        ],
      ),
    );
  }

  void _showChangePasswordSheet(BuildContext context) {
    final oldPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // Local state for visibility toggles
    final RxBool obscureOld = true.obs;
    final RxBool obscureNew = true.obs;
    final RxBool obscureConfirm = true.obs;

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                      Text('Change Password', style: Theme.of(context).textTheme.titleLarge),
                      IconButton(onPressed: () => Get.back(), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Old Password
                  Obx(() => TextFormField(
                    controller: oldPassController,
                    obscureText: obscureOld.value,
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscureOld.value ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => obscureOld.toggle(),
                      ),
                    ),
                    validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                  )),
                  const SizedBox(height: 16),

                  // New Password
                  Obx(() => TextFormField(
                    controller: newPassController,
                    obscureText: obscureNew.value,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscureNew.value ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => obscureNew.toggle(),
                      ),
                    ),
                    validator: (val) => val == null || val.length < 6 ? 'Minimum 6 characters required' : null,
                  )),
                  const SizedBox(height: 16),

                  // Confirm Password
                  Obx(() => TextFormField(
                    controller: confirmPassController,
                    obscureText: obscureConfirm.value,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: const Icon(Icons.check_circle_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm.value ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => obscureConfirm.toggle(),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'Required';
                      if (val != newPassController.text) return 'Passwords do not match';
                      return null;
                    },
                  )),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: Obx(() => ElevatedButton(
                      onPressed: controller.isUpdating.value ? null : () {
                        if (formKey.currentState!.validate()) {
                          controller.changePassword(oldPassController.text, newPassController.text);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                      ),
                      child: controller.isUpdating.value
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : const Text('Update Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    )),
                  ),
                  SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
                ],
              ),
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
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
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditableRow(BuildContext context, String label, String value, IconData icon, VoidCallback onEdit) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
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
}