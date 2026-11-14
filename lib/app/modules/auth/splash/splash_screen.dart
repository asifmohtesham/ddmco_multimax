import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/auth/splash/splash_controller.dart';

class SplashScreen extends GetView<SplashController> {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.business_sharp, size: 100, color: Colors.grey[400]),
              const SizedBox(height: 48.0),
              const CircularProgressIndicator(),
              const SizedBox(height: 24.0),
              Obx(() => Text(
                    controller.isSlow.value
                        ? 'Still trying to reach the server…'
                        : 'Checking your session…',
                    textAlign: TextAlign.center,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
