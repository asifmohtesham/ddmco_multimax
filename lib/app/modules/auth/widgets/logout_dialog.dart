import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';

/// Logout confirmation that turns into its own loading state.
///
/// One dialog, two states — never a second route stacked on top. While
/// [busy] is true the action shows a spinner, Cancel is disabled, and the
/// dialog cannot be dismissed by barrier tap or system back. The owner sets
/// and clears [busy] and publishes a failure through [error].
class LogoutDialog extends StatelessWidget {
  final RxBool busy;
  final RxnString error;
  final String? email;
  final VoidCallback onConfirm;

  const LogoutDialog({
    super.key,
    required this.busy,
    required this.error,
    required this.onConfirm,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final account = email;

    return Obx(() {
      final isBusy = busy.value;
      final failure = error.value;
      return PopScope(
        canPop: !isBusy,
        child: AlertDialog(
          title: const Text('Log out?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                account == null || account.isEmpty
                    ? "You'll need to sign in again."
                    : "You'll need to sign in again as $account.",
                style: TextStyle(color: s.textMuted),
              ),
              if (failure != null) ...[
                const SizedBox(height: AppSpace.s3),
                Text(
                  failure,
                  style: TextStyle(
                    color: isDark ? AppColors.red300 : AppColors.red700,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isBusy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            AsyncFilledButton(
              busy: busy,
              onPressed: onConfirm,
              icon: const Icon(Icons.logout, size: 18),
              label: 'Log out',
              loadingLabel: 'Logging out…',
              spinnerColor: Colors.white,
              // Keep the red fill while disabled-by-busy so the white
              // spinner and label stay readable.
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.red700,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.red700,
                disabledForegroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    });
  }
}
