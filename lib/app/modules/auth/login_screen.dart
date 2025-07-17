import 'dart:io'; // For File
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/auth/login_controller.dart'; // Update path

class LoginScreen extends GetView<LoginController> {
  const LoginScreen({super.key});

  // Function to check for logo existence
  Widget _buildLogo() {
    // Define potential logo paths
    const String logoPng = 'assets/images/logo.png';
    const String logoJpg = 'assets/images/logo.jpg';
    const String logoJpeg = 'assets/images/logo.jpeg';

    // Check which logo exists (this is a simplified synchronous check at build time)
    // For more dynamic scenarios or network images, use FutureBuilder or other async widgets.
    String? logoPath;
    // Note: A direct File check like this won't work for Flutter assets during runtime
    // as they are bundled. Instead, rely on Flutter's asset handling.
    // We'll use a try-catch with Image.asset.

    // A more robust way to handle multiple extensions for assets is usually
    // to decide on ONE filename and use that. But to meet the prompt:
    try {
      // Try loading png, then jpg, then jpeg.
      // This is not the most efficient way. It's better to know the exact filename.
      // For this example, we'll just try 'logo.png' and fallback.
      // A truly dynamic check of asset existence is tricky without listing all assets.
      // We assume if one is provided, it's the one to use.
      // If you need to *check* existence from multiple options, it's usually better to
      // have that logic determined during your build process or have a config.
      // For simplicity, we'll try to load 'logo.png' and if it fails, show placeholder.

      return Image.asset(
        logoPng, // Prioritize png
        height: 150,
        errorBuilder: (context, error, stackTrace) {
          // Attempt jpg if png fails
          return Image.asset(
            logoJpg,
            height: 150,
            errorBuilder: (context, error, stackTrace) {
              // Attempt jpeg if jpg fails
              return Image.asset(
                logoJpeg,
                height: 150,
                errorBuilder: (context, error, stackTrace) {
                  // If all fail, show placeholder
                  return Icon(Icons.business_sharp, size: 100, color: Colors.grey[400]);
                },
              );
            },
          );
        },
      );
    } catch (e) {
      // Fallback if no logo is found (or if the primary attempt throws before errorBuilder)
      return Icon(Icons.business_sharp, size: 100, color: Colors.grey[400]);
    }
  }


  @override
  Widget build(BuildContext context) {
    // You might want to register the controller here if not using bindings
    // Get.lazyPut(() => LoginController()); // Or Get.put() if needed immediately

    return Scaffold(
      body: Center(
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
                    labelText: 'Email',
                    hintText: 'Enter your email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
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
                // Add links for "Forgot Password?" or "Sign Up" if needed
              ],
            ),
          ),
        ),
      ),
    );
  }
}
