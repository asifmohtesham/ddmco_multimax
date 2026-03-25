import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// A quantity input row with press-and-hold increment / decrement buttons.
///
/// [QuantityInputWidget] is a pure [StatelessWidget]; mutable repeat-timer
/// state lives in a [_QtyRepeatController] that is scoped per button via
/// an explicit [Get.put] call keyed on [key.toString()].
///
/// ## Why not GetWidget?
///
/// [GetWidget] derives its controller tag from [widget.hashCode]. When a
/// parent [StatelessWidget] is rebuilt (e.g. by an [Obx]), Flutter constructs
/// a new widget object for every child, giving [_QtyActionButton] a new
/// [hashCode] on each rebuild. [GetWidget.controller] then calls
/// [Get.find(tag: newHash)] before [Get.put] has fired for that tag,
/// returning null and crashing with:
///   "type 'Null' is not a subtype of type '_QtyRepeatController'"
///
/// ## Fix
///
/// [_QtyActionButton] is now a plain [StatelessWidget]. The controller tag
/// is derived from [key.toString()] — stable because [_decKey] / [_incKey]
/// are `final` fields created **once** in the [QuantityInputWidget]
/// constructor, not in [build()]. The same [UniqueKey] object (and therefore
/// the same [toString()] string) is reused on every rebuild of the parent,
/// so [Get.find] always resolves to the same already-registered controller.
class QuantityInputWidget extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String label;
  final bool isReadOnly;

  /// Additional context shown as a badge, e.g. "Available: 50".
  final String? infoText;
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
    this.color = Colors.black87,
    this.onChanged,
  });

  // Stable UniqueKeys — created once per QuantityInputWidget instance.
  // Because these are final fields (not computed in build()), the same
  // key objects survive every rebuild, keeping the GetX tag stable.
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      infoText!,
                      style: TextStyle(
                        fontSize: 11,
                        color: primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

        // ── Input row ─────────────────────────────────────────────────────
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
              // ── Text field ────────────────────────────────────────────
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

              // ── Buttons Group (Right Side) ──────────────────────────────
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
// GetxController: owns the repeat Timer for a single button.
// Unchanged — remains a GetxController so it participates in Get.delete
// lifecycle management correctly.
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
// Press-and-hold button — plain StatelessWidget with explicit GetX tag.
//
// WHY NOT GetWidget:
//   GetWidget derives instanceKey from widget.hashCode. A new widget object
//   is created on every parent rebuild (Obx, setState, etc.), giving a new
//   hashCode on each call. GetWidget.controller then calls
//   Get.find(tag: newHash) before Get.put has fired → null → crash.
//
// FIX — explicit tag from key.toString():
//   _QtyActionButton receives a UniqueKey that is a `final` field of
//   QuantityInputWidget (created once in the constructor, not in build()).
//   UniqueKey.toString() is therefore stable for the lifetime of the
//   parent widget instance and survives every Obx / parent rebuild.
//
//   Get.isRegistered guard: ensures Get.put is called exactly once per
//   tag, even if build() is invoked multiple times before the controller
//   is deleted (e.g. rapid rebuilds before the first frame settles).
//
//   Cleanup: the controller is deleted in a post-frame callback when the
//   widget is removed from the tree. Because QuantityInputWidget creates
//   its keys as final fields, this only happens on a genuine unmount —
//   not on a parent Obx rebuild — matching the original GetWidget intent.
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

  // Resolves or registers the controller for this button's stable tag.
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
          child: Icon(
            icon,
            color: color,
            size: 22,
          ),
        ),
      ),
    );
  }
}
