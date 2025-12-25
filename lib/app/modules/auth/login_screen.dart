import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/login_controller.dart';

class LoginScreen extends GetView<LoginController> {
  const LoginScreen({super.key});

  Widget _buildLogo() {
    return Icon(Icons.business_sharp, size: 100, color: Colors.grey[400]);
  }

  void _showServerConfigSheet(BuildContext context) {
    // Reset guide flag when user opens the sheet
    controller.showServerGuide.value = false;

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connect to Instance', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Enter the URL of your instance.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              TextField(
                controller: controller.serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://erp.domain.com',
                  prefixIcon: Icon(Icons.link),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: Obx(() => ElevatedButton(
                  onPressed: controller.isCheckingConnection.value ? null : controller.saveServerConfiguration,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: controller.isCheckingConnection.value
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Connect'),
                )),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Add an AppBar-like structure or just a safe area with the settings icon
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
                      // keyboardType: TextInputType.emailAddress,
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
                              Get.snackbar('Info', 'Please enter your email address in the field above first.', backgroundColor: Colors.blue, colorText: Colors.white);
                            } else {
                              Get.defaultDialog(
                                  title: 'Reset Password',
                                  middleText: 'Send password reset instructions to ${controller.emailController.text}?',
                                  textConfirm: 'Send',
                                  textCancel: 'Cancel',
                                  confirmTextColor: Colors.white,
                                  onConfirm: () {
                                    Get.back(); // close dialog
                                    controller.resetPassword();
                                  }
                              );
                            }
                          },
                          child: const Text('Forgot Password?')
                      ),
                    ),

                    const SizedBox(height: 24.0),
                    Obx(() => controller.isLoading.value
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
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

          // Settings Icon with Guide Overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Obx(() => Stack(
              alignment: Alignment.center,
              children: [
                // Pulse effect or guide background if calling for attention
                if (controller.showServerGuide.value)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.orange.withValues(alpha: 0.3),
                      border: Border.all(color: Colors.orange, width: 2),
                    ),
                  ),

                IconButton(
                  icon: Icon(
                      Icons.settings,
                      color: controller.showServerGuide.value ? Colors.orange : Colors.grey
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