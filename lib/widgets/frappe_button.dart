import 'package:flutter/material.dart';
import '../theme/frappe_theme.dart';

// ==============================================================================
// 1. BASE BUTTON (Configurable)
// ==============================================================================

class FrappeButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final FrappeButtonStyle style;
  final bool isFullWidth;
  final bool isLoading;

  const FrappeButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.style = FrappeButtonStyle.primary,
    this.isFullWidth = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Determine Colors based on Style
    Color bgColor;
    Color fgColor;
    BorderSide? border;

    switch (style) {
      case FrappeButtonStyle.primary:
        bgColor = FrappeTheme.primary;
        fgColor = Colors.white;
        border = BorderSide.none;
        break;
      case FrappeButtonStyle.secondary:
        bgColor = Colors.white;
        fgColor = FrappeTheme.textBody;
        border = BorderSide(color: Colors.grey.shade300);
        break;
      case FrappeButtonStyle.tonal:
        bgColor = FrappeTheme.primary.withValues(alpha: 0.1);
        fgColor = FrappeTheme.primary;
        border = BorderSide.none;
        break;
      case FrappeButtonStyle.danger:
        bgColor = Colors.red.shade50;
        fgColor = Colors.red.shade700;
        border = BorderSide.none; // or BorderSide(color: Colors.red.shade200);
        break;
    }

    // 2. Build Button content
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: fgColor
              )
          ),
          const SizedBox(width: 8),
          Text("Processing...", style: TextStyle(color: fgColor, fontWeight: FontWeight.w600)),
        ] else ...[
          if (icon != null) ...[
            Icon(icon, size: 18, color: fgColor),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              color: fgColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ]
      ],
    );

    // 3. Construct the Button
    Widget button = Material(
      color: onPressed == null ? Colors.grey.shade300 : bgColor,
      borderRadius: BorderRadius.circular(FrappeTheme.radius),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(FrappeTheme.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FrappeTheme.radius),
            border: border != null && onPressed != null ? Border.fromBorderSide(border) : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

enum FrappeButtonStyle { primary, secondary, tonal, danger }

// ==============================================================================
// 2. SPECIALIZED CRUD WIDGETS
// ==============================================================================

/// Standard "Create" Action (e.g. Save, Submit, New)
/// Usage: FrappeCreateButton(onPressed: () => controller.save())
class FrappeCreateButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool isFullWidth;
  final bool isLoading;

  const FrappeCreateButton({
    super.key,
    required this.onPressed,
    this.label = 'Create',
    this.isFullWidth = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return FrappeButton(
      label: label,
      icon: Icons.add,
      onPressed: onPressed,
      style: FrappeButtonStyle.primary, // Blue
      isFullWidth: isFullWidth,
      isLoading: isLoading,
    );
  }
}

/// Standard "Edit" Action (e.g. Open Form in Edit Mode)
class FrappeEditButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const FrappeEditButton({
    super.key,
    required this.onPressed,
    this.label = 'Edit',
  });

  @override
  Widget build(BuildContext context) {
    return FrappeButton(
      label: label,
      icon: Icons.edit_outlined,
      onPressed: onPressed,
      style: FrappeButtonStyle.tonal, // Light Blue background
    );
  }
}

/// Standard "View" or "Read" Action (e.g. View Details)
class FrappeViewButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const FrappeViewButton({
    super.key,
    required this.onPressed,
    this.label = 'View',
  });

  @override
  Widget build(BuildContext context) {
    return FrappeButton(
      label: label,
      icon: Icons.visibility_outlined,
      onPressed: onPressed,
      style: FrappeButtonStyle.secondary, // White with border
    );
  }
}

/// Standard "Delete" Action (e.g. Remove Item)
class FrappeDeleteButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const FrappeDeleteButton({
    super.key,
    required this.onPressed,
    this.label = 'Delete',
  });

  @override
  Widget build(BuildContext context) {
    return FrappeButton(
      label: label,
      icon: Icons.delete_outline,
      onPressed: onPressed,
      style: FrappeButtonStyle.danger, // Light Red background
    );
  }
}

// ==============================================================================
// 3. ICON ONLY VARIANTS (For Headers/Lists)
// ==============================================================================

class FrappeIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final FrappeButtonStyle style;
  final String? tooltip;

  const FrappeIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.style = FrappeButtonStyle.secondary,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    Color bgColor;

    switch (style) {
      case FrappeButtonStyle.primary:
        color = Colors.white;
        bgColor = FrappeTheme.primary;
        break;
      case FrappeButtonStyle.danger:
        color = Colors.red;
        bgColor = Colors.red.shade50;
        break;
      case FrappeButtonStyle.tonal:
        color = FrappeTheme.primary;
        bgColor = FrappeTheme.primary.withValues(alpha: 0.1);
        break;
      case FrappeButtonStyle.secondary:
      default:
        color = FrappeTheme.textBody;
        bgColor = Colors.transparent;
        break;
    }

    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, color: color, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}