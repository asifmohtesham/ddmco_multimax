import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/auth/splash/splash_controller.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';

class SplashScreen extends GetView<SplashController> {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.scheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Obx(() => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.business_sharp,
                      size: 100,
                      color: scheme.textSubtle,
                    ),
                    const SizedBox(height: 48),
                    if (controller.isSessionVerificationPending.value) ...[
                      Text(
                        "Can't reach the server.",
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.text,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We’ll retry automatically.',
                        style: TextStyle(color: scheme.textMuted),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      AsyncFilledButton(
                        busy: controller.isCheckingSession,
                        onPressed: controller.retry,
                        icon: const Icon(Icons.refresh),
                        label: 'Retry',
                        loadingLabel: 'Checking…',
                        style: FilledButton.styleFrom(
                          disabledBackgroundColor: scheme.primary,
                          disabledForegroundColor: scheme.onPrimary,
                        ),
                      ),
                      Obx(() => TextButton(
                            onPressed: controller.isCheckingSession.value
                                ? null
                                : controller.openLogin,
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.text,
                            ),
                            child: const Text('Go to Login'),
                          )),
                    ] else ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                      Text(
                        controller.isSlow.value
                            ? 'Still trying to reach the server…'
                            : 'Checking your session…',
                        style: TextStyle(color: scheme.textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                )),
          ),
        ),
      ),
    );
  }
}
