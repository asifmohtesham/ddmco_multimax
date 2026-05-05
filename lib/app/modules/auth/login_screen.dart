import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/login_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:flutter/services.dart';

class LoginScreen extends GetView<LoginController> {
  const LoginScreen({super.key});

  Widget _buildLogo() {
    return Icon(Icons.business_sharp, size: 100, color: Colors.grey[400]);
  }

  void _showServerConfigSheet(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    Get.bottomSheet(
      GetBuilder<LoginController>(
        builder: (c) => Container(
          padding: EdgeInsets.only(
            left: 24.0,
            right: 24.0,
            top: 24.0,
            bottom: viewInsets.bottom + 24.0,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              // lets the content move above the keyboard instead of overflowing
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect to Instance',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the URL of your ERP instance.',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  if (c.currentServerUrl.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Current: ${c.currentServerUrl.value}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextField(
                    controller: c.serverUrlController,
                    decoration: InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'https://erp.domain.com',
                      prefixIcon: const Icon(Icons.link),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste),
                        tooltip: 'Paste from clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          final text = data?.text?.trim();
                          if (text != null && text.isNotEmpty) {
                            c.serverUrlController
                              ..text = text
                              ..selection = TextSelection.fromPosition(
                                TextPosition(offset: text.length),
                              );
                          }
                        },
                      ),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                    autocorrect: false,
                    onSubmitted: (_) => c.saveServerConfiguration(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: c.isCheckingConnection.value
                          ? null
                          : c.saveServerConfiguration,
                      style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      child: c.isCheckingConnection.value
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Connect'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
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
              onPressed: () {
                // 1) Dismiss any open keyboard from the login form.
                FocusManager.instance.primaryFocus?.unfocus();

                // 2) Open the server config sheet on the next frame,
                //    after viewInsets have been updated.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showServerConfigSheet(context);
                });
              },
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
