import 'package:flutter/material.dart';
import 'package:multimax/theme/frappe_theme.dart';
import 'package:multimax/widgets/frappe_button.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';

class FrappeFormLayout extends StatelessWidget {
  final String title;
  final String? status;
  final bool isLoading;
  final Widget body;
  final VoidCallback? onSave;
  final String saveLabel;
  final List<Widget>? actions;
  final PreferredSizeWidget? appBarBottom; // For TabBar support

  const FrappeFormLayout({
    super.key,
    required this.title,
    required this.body,
    this.status,
    this.isLoading = false,
    this.onSave,
    this.saveLabel = 'Save',
    this.actions,
    this.appBarBottom,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FrappeTheme.surface,
      appBar: MainAppBar(
        title: title,
        showBack: true,
        // Assuming MainAppBar accepts status based on previous BatchScreen code
        // If not, remove this line and put status in body
        // status: status,
        actions: actions,
        bottom: appBarBottom,
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: FrappeTheme.primary),
            )
          : body,

      // THE GLOBAL FIX:
      bottomNavigationBar: onSave != null ? _buildStickyFooter(context) : null,
    );
  }

  Widget _buildStickyFooter(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          // Wraps button in a min-sized column to prevent expansion
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FrappeButton(
                label: saveLabel,
                icon: Icons.save_outlined,
                style: FrappeButtonStyle.primary,
                isFullWidth: true,
                onPressed: onSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
