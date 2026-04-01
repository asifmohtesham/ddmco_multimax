import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/login_controller.dart';

class LoginScreen extends GetView<LoginController> {
  const LoginScreen({super.key});

  Widget _buildLogo() {
    return Icon(Icons.business_sharp, size: 100, color: Colors.grey[400]);
  }

  // ---------------------------------------------------------------------------
  // Server-config bottom sheet — multi-field server search
  // ---------------------------------------------------------------------------

  void _showServerConfigSheet(BuildContext context) {
    controller.showServerGuide.value = false;
    // Refresh saved history before opening
    controller.refreshServerHistory();

    Get.bottomSheet(
      _ServerConfigSheet(controller: controller),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: controller.loginFormKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildLogo(),
                    const SizedBox(height: 48.0),
                    TextFormField(
                      controller: controller.emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email / Username',
                        hintText: 'Enter your email or username',
                        prefixIcon: Icon(Icons.email),
                        border: OutlineInputBorder(),
                      ),
                      validator: controller.validateEmail,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                    ),
                    const SizedBox(height: 16.0),
                    Obx(() => TextFormField(
                          controller: controller.passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                controller.isPasswordHidden.value
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: controller.togglePasswordVisibility,
                            ),
                          ),
                          obscureText: controller.isPasswordHidden.value,
                          validator: controller.validatePassword,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                        )),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          if (controller.emailController.text.isEmpty) {
                            Get.snackbar(
                              'Info',
                              'Please enter your email address in the field above first.',
                              backgroundColor: Colors.blue,
                              colorText: Colors.white,
                            );
                          } else {
                            Get.defaultDialog(
                              title: 'Reset Password',
                              middleText:
                                  'Send password reset instructions to ${controller.emailController.text}?',
                              textConfirm: 'Send',
                              textCancel: 'Cancel',
                              confirmTextColor: Colors.white,
                              onConfirm: () {
                                Get.back();
                                controller.resetPassword();
                              },
                            );
                          }
                        },
                        child: const Text('Forgot Password?'),
                      ),
                    ),
                    const SizedBox(height: 24.0),
                    Obx(() => controller.isLoading.value
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16.0),
                              textStyle: const TextStyle(fontSize: 16),
                            ),
                            onPressed: controller.loginUser,
                            child: const Text('Login'),
                          )),
                  ],
                ),
              ),
            ),
          ),

          // Settings icon (with optional guide highlight)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Obx(() => Stack(
                  alignment: Alignment.center,
                  children: [
                    if (controller.showServerGuide.value)
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.orange.withValues(alpha: 0.3),
                          border:
                              Border.all(color: Colors.orange, width: 2),
                        ),
                      ),
                    IconButton(
                      icon: Icon(
                        Icons.settings,
                        color: controller.showServerGuide.value
                            ? Colors.orange
                            : Colors.grey,
                      ),
                      tooltip: 'Server Configuration',
                      onPressed: () => _showServerConfigSheet(context),
                    ),
                  ],
                )),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// _ServerConfigSheet — extracted widget so Obx rebuilds are scoped
// =============================================================================

class _ServerConfigSheet extends StatelessWidget {
  const _ServerConfigSheet({required this.controller});

  final LoginController controller;

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Text(
              'Connect to Instance',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Enter the URL of your ERPNext instance or pick a recent one.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // ── URL entry + Connect button ───────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller.serverUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://erp.domain.com',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => controller.saveServerConfiguration(),
                  ),
                ),
                const SizedBox(width: 8),
                Obx(() => SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: controller.isCheckingConnection.value
                            ? null
                            : controller.saveServerConfiguration,
                        style: ElevatedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: controller.isCheckingConnection.value
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text('Connect'),
                      ),
                    )),
              ],
            ),

            // ── Saved-server search section (only if history is non-empty) ─
            Obx(() {
              if (controller.savedServerUrls.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Recent Servers',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),

                  // Search/filter field
                  TextField(
                    controller: controller.searchController,
                    decoration: InputDecoration(
                      hintText: 'Search saved servers…',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                      suffixIcon: Obx(() => controller
                                  .searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: controller.searchController.clear,
                                  tooltip: 'Clear search',
                                )
                              : const SizedBox.shrink()),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Results list (max 5 visible, scrollable)
                  Obx(() {
                    final items = controller.filteredServerUrls;
                    if (items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            'No matching servers found.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      );
                    }
                    return ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          final url = items[index];
                          return Dismissible(
                            key: ValueKey(url),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding:
                                  const EdgeInsets.only(right: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.delete,
                                  color: Colors.white),
                            ),
                            onDismissed: (_) =>
                                controller.deleteSavedUrl(url),
                            child: ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                    color: Colors.grey.shade200),
                              ),
                              leading: const Icon(Icons.history,
                                  size: 18, color: Colors.grey),
                              title: Text(
                                url,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 14,
                                  color: Colors.grey),
                              onTap: () =>
                                  controller.selectSavedUrl(url),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                ],
              );
            }),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
