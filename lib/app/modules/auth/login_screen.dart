import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/login_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class LoginScreen extends GetView<LoginController> {
  const LoginScreen({super.key});

  Widget _buildLogo() {
    return Icon(Icons.business_sharp, size: 100, color: Colors.grey[400]);
  }

  Widget _buildSettingsIcon(BuildContext context) {
    return GetBuilder<LoginController>(
      builder: (c) {
        final showGuide = c.showServerGuide.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            if (showGuide)
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
                color: showGuide ? Colors.orange : Colors.grey,
              ),
              tooltip: 'Server Configuration',
              onPressed: () => c.openConnectSheet(context),
            ),
          ],
        );
      },
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
                // Commit 3: AutofillGroup enables Android credential manager
                // and third-party password managers to autofill both fields.
                child: AutofillGroup(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildLogo(),
                      const SizedBox(height: 48.0),
                      // Commit 2 + 3 + 5: keyboard type, action chaining,
                      // autofill hints, autocorrect off.
                      TextFormField(
                        controller: controller.emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email / Username',
                          hintText: 'Enter your email or username',
                          prefixIcon: Icon(Icons.email),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        validator: controller.validateEmail,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                      const SizedBox(height: 16.0),
                      // Commit 2 + 3 + 5: action done triggers login,
                      // autofill hints, suggestions off.
                      ValueListenableBuilder<bool>(
                        valueListenable: controller.isPasswordHidden,
                        builder: (context, isHidden, _) => TextFormField(
                          controller: controller.passwordController,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(Icons.lock),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                isHidden
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: controller.togglePasswordVisibility,
                            ),
                          ),
                          obscureText: isHidden,
                          textInputAction: TextInputAction.done,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) => controller.loginUser(),
                          validator: controller.validatePassword,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: GetBuilder<LoginController>(
                          builder: (c) => TextButton(
                            onPressed: () {
                              if (c.isLoading.value) return;
                              if (controller.emailController.text.isEmpty) {
                                // Commit 5: use GlobalSnackbar for consistency.
                                GlobalSnackbar.info(
                                  message:
                                      'Please enter your email address in the field above first.',
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
                      ),
                      const SizedBox(height: 24.0),
                      GetBuilder<LoginController>(
                        builder: (c) => ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16.0),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                          onPressed: c.isLoading.value ? null : c.loginUser,
                          child: c.isLoading.value
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Login'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: _buildSettingsIcon(context),
          ),
        ],
      ),
    );
  }
}
