import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/login_controller.dart';
import 'package:multimax/theme/frappe_theme.dart'; // Ensure this import points to your new theme file

class LoginScreen extends GetView<LoginController> {
  const LoginScreen({super.key});

  Widget _buildLogo() {
    // Kept the original logic, just ensured it sits well on the new surface
    return Icon(Icons.business_sharp, size: 80, color: Colors.grey[400]);
  }

  void _showServerConfigSheet(BuildContext context) {
    // Reset guide flag when user opens the sheet
    controller.showServerGuide.value = false;

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24.0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(FrappeTheme.radius * 2)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Espresso Style Heading
              Text(
                  'Connect to Instance',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: FrappeTheme.textBody
                  )
              ),
              const SizedBox(height: 8),
              const Text(
                  'Enter the URL of your Frappe/ERPNext instance.',
                  style: TextStyle(color: FrappeTheme.textLabel)
              ),
              const SizedBox(height: 24),

              // New Theme Input
              TextField(
                controller: controller.serverUrlController,
                decoration: FrappeTheme.inputDecoration('Server URL').copyWith(
                  hintText: 'https://erp.domain.com',
                  prefixIcon: const Icon(Icons.link, color: FrappeTheme.textLabel),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 24),

              // New Theme Button
              SizedBox(
                width: double.infinity,
                child: Obx(() => ElevatedButton(
                  onPressed: controller.isCheckingConnection.value ? null : controller.saveServerConfiguration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FrappeTheme.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FrappeTheme.radius),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: controller.isCheckingConnection.value
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Connect', style: TextStyle(fontWeight: FontWeight.w600)),
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
      backgroundColor: FrappeTheme.surface, // Espresso background color
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

                    // -- Email Field --
                    TextFormField(
                      controller: controller.emailController,
                      decoration: FrappeTheme.inputDecoration('Email / Username').copyWith(
                        hintText: 'user@example.com',
                        prefixIcon: const Icon(Icons.email_outlined, color: FrappeTheme.textLabel),
                      ),
                      validator: controller.validateEmail,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      style: const TextStyle(color: FrappeTheme.textBody),
                    ),

                    const SizedBox(height: FrappeTheme.spacing),

                    // -- Password Field --
                    Obx(() => TextFormField(
                      controller: controller.passwordController,
                      decoration: FrappeTheme.inputDecoration('Password').copyWith(
                        prefixIcon: const Icon(Icons.lock_outline, color: FrappeTheme.textLabel),
                        suffixIcon: IconButton(
                          icon: Icon(
                            controller.isPasswordHidden.value
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: FrappeTheme.textLabel,
                          ),
                          onPressed: controller.togglePasswordVisibility,
                        ),
                      ),
                      obscureText: controller.isPasswordHidden.value,
                      validator: controller.validatePassword,
                      autovalidateMode: AutovalidateMode.onUserInteraction,
                      style: const TextStyle(color: FrappeTheme.textBody),
                    )),

                    // -- Forgot Password --
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                          onPressed: () {
                            if (controller.emailController.text.isEmpty) {
                              Get.snackbar(
                                  'Info',
                                  'Please enter your email address in the field above first.',
                                  backgroundColor: FrappeTheme.textBody,
                                  colorText: Colors.white,
                                  margin: const EdgeInsets.all(16),
                                  borderRadius: FrappeTheme.radius
                              );
                            } else {
                              Get.defaultDialog(
                                  title: 'Reset Password',
                                  titleStyle: const TextStyle(fontWeight: FontWeight.bold),
                                  middleText: 'Send password reset instructions to ${controller.emailController.text}?',
                                  textConfirm: 'Send',
                                  textCancel: 'Cancel',
                                  confirmTextColor: Colors.white,
                                  buttonColor: FrappeTheme.primary,
                                  radius: FrappeTheme.radius,
                                  onConfirm: () {
                                    Get.back(); // close dialog
                                    controller.resetPassword();
                                  }
                              );
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: FrappeTheme.primary,
                          ),
                          child: const Text('Forgot Password?')
                      ),
                    ),

                    const SizedBox(height: 24.0),

                    // -- Login Button --
                    Obx(() => SizedBox(
                      height: 50,
                      child: controller.isLoading.value
                          ? const Center(child: CircularProgressIndicator())
                          : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: FrappeTheme.primary,
                          foregroundColor: Colors.white,
                          elevation: 0, // Flat design
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(FrappeTheme.radius),
                          ),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        onPressed: controller.loginUser,
                        child: const Text('Login'),
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ),

          // -- Settings Icon (Server Config) --
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Obx(() => Stack(
              alignment: Alignment.center,
              children: [
                // Pulse effect / Guide background
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
                      Icons.settings_outlined,
                      color: controller.showServerGuide.value ? Colors.orange : FrappeTheme.textLabel
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