import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// A quantity input row with press-and-hold increment / decrement buttons.
///
/// [QuantityInputWidget] is a pure [StatelessWidget]; mutable repeat-timer
/// state lives in a [_QtyRepeatController] scoped per button via an explicit
/// [Get.put] call keyed on [key.toString()].
///
/// Commit C-3: tappable Max badge
///   When [onInfoTap] is provided the infoText badge becomes an [InkWell]
///   with a small info_outline icon appended to signal tappability.
///   When null the badge renders exactly as before — no visual regression
///   for callers that do not supply the callback.
class QuantityInputWidget extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String label;
  final bool isReadOnly;

  /// Short badge string rendered next to the label, e.g. 'Max: 3'.
  final String? infoText;

  /// Optional callback fired when the user taps the info badge.
  /// Supply this to show a breakdown dialog/sheet (e.g. tooltip).
  /// When null the badge is non-interactive.
  final VoidCallback? onInfoTap;

  final Color color;
  final Function(String)? onChanged;

  QuantityInputWidget({
    super.key,
    required this.controller,
    required this.onIncrement,
    required this.onDecrement,
    this.label = 'Quantity',
    this.isReadOnly = false,
    this.infoText,
    this.onInfoTap,
    this.color = Colors.black87,
    this.onChanged,
  });

  final UniqueKey _decKey = UniqueKey();
  final UniqueKey _incKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final borderColor  = Colors.grey.shade300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header Row: Label + Info Badge ─────────────────────────────────
        if (label.isNotEmpty || (infoText != null && infoText!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                if (infoText != null && infoText!.isNotEmpty)
                  _InfoBadge(
                    text: infoText!,
                    primaryColor: primaryColor,
                    onTap: onInfoTap,
                  ),
              ],
            ),
          ),

        // ── Input row ─────────────────────────────────────────────────
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: isReadOnly ? Colors.grey.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: isReadOnly
                ? []
                : [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: controller,
                  readOnly: isReadOnly,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: isReadOnly
                        ? Colors.grey.shade600
                        : Colors.black87,
                  ),
                  onChanged: onChanged,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16),
                    hintText: '0',
                    isDense: true,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return null;
                    final qty = double.tryParse(value);
                    if (qty == null || qty < 0) return 'Invalid';
                    return null;
                  },
                ),
              ),
              if (!isReadOnly) ...[
                Container(
                    width: 1, height: 32, color: Colors.grey.shade200),
                _QtyActionButton(
                  key: _decKey,
                  icon: Icons.remove,
                  onPressed: onDecrement,
                  color: Colors.grey.shade700,
                ),
                Container(
                    width: 1, height: 32, color: Colors.grey.shade200),
                _QtyActionButton(
                  key: _incKey,
                  icon: Icons.add,
                  onPressed: onIncrement,
                  color: primaryColor,
                  borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(11)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _InfoBadge
//
// Renders the infoText pill.
//   • When [onTap] is null  → plain Container, identical to the old badge.
//   • When [onTap] is given → InkWell wraps the pill; a small info_outline
//     icon is appended to signal interactivity.
// ---------------------------------------------------------------------------
class _InfoBadge extends StatelessWidget {
  final String text;
  final Color primaryColor;
  final VoidCallback? onTap;

  const _InfoBadge({
    required this.text,
    required this.primaryColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.info_outline,
              size: 12,
              color: primaryColor.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return badge;

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: badge,
    );
  }
}

// ---------------------------------------------------------------------------
// GetxController: owns the repeat Timer for a single button.
// ---------------------------------------------------------------------------
class _QtyRepeatController extends GetxController {
  Timer? _repeatTimer;

  void startRepeat(VoidCallback action) {
    action();
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(
        const Duration(milliseconds: 150), (_) => action());
  }

  void stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void onClose() {
    _repeatTimer?.cancel();
    super.onClose();
  }
}

// ---------------------------------------------------------------------------
// Press-and-hold button.
// ---------------------------------------------------------------------------
class _QtyActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final BorderRadius? borderRadius;

  const _QtyActionButton({
    required super.key,
    required this.icon,
    required this.onPressed,
    required this.color,
    this.borderRadius,
  });

  _QtyRepeatController _controller() {
    final tag = key.toString();
    if (!Get.isRegistered<_QtyRepeatController>(tag: tag)) {
      Get.put(_QtyRepeatController(), tag: tag, permanent: false);
    }
    return Get.find<_QtyRepeatController>(tag: tag);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius ?? BorderRadius.zero,
        onTapDown: (_) {
          HapticFeedback.lightImpact();
          ctrl.startRepeat(onPressed);
        },
        onTapUp:     (_) => ctrl.stopRepeat(),
        onTapCancel: ()  => ctrl.stopRepeat(),
        child: SizedBox(
          width: 56,
          height: double.infinity,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}
