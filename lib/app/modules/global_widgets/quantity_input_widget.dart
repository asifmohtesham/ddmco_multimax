import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Quantity input with +/- action buttons.
///
/// Converted from [StatelessWidget] to [StatefulWidget] so that
/// [didUpdateWidget] can detect when the parent passes a *new*
/// [TextEditingController] instance (which happens when GetX disposes
/// and recreates the parent controller mid-Obx-rebuild). Without this
/// guard, [TextFormField]'s internal [_AnimatedState] calls
/// [addListener] on the old, already-disposed controller and crashes.
class QuantityInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String label;
  final bool isReadOnly;

  /// Additional context like "Available: 50" or "Ordered: 10"
  final String? infoText;
  final Color color;
  final Function(String)? onChanged;

  const QuantityInputWidget({
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

  @override
  State<QuantityInputWidget> createState() => _QuantityInputWidgetState();
}

class _QuantityInputWidgetState extends State<QuantityInputWidget> {
  // Holds the controller currently wired into our TextFormField.
  // When the parent rebuilds with a new controller instance we swap
  // this reference so Flutter never tries to attach a listener to a
  // disposed ChangeNotifier.
  late TextEditingController _activeController;

  @override
  void initState() {
    super.initState();
    _activeController = widget.controller;
  }

  @override
  void didUpdateWidget(QuantityInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      // The parent supplied a different controller instance.
      // Update our reference so the TextFormField below uses the live one.
      _activeController = widget.controller;
    }
  }

  // We do NOT dispose _activeController here – it is owned by the
  // parent GetxController (or State) and will be disposed there.

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row: Label + Info Badge
        if (widget.label.isNotEmpty ||
            (widget.infoText != null && widget.infoText!.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (widget.infoText != null && widget.infoText!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.infoText!,
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

        // Input Control Container
        Row(
          children: [
            // Text Field (Left Side)
            Expanded(
              child: TextFormField(
                controller: _activeController,
                readOnly: widget.isReadOnly,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: widget.isReadOnly
                      ? Colors.grey.shade600
                      : Colors.black87,
                ),
                onChanged: widget.onChanged,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d*')),
                ],
                decoration: InputDecoration(
                  label: Text(widget.label),
                  border: InputBorder.none,
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

            // Buttons Group (Right Side)
            if (!widget.isReadOnly) ...[
              // Vertical Divider
              Container(
                  width: 1, height: 32, color: Colors.grey.shade200),

              // Decrement Button
              _buildActionButton(
                icon: Icons.remove,
                onPressed: widget.onDecrement,
                colour: Colors.grey.shade700,
              ),

              // Vertical Divider between buttons
              Container(
                  width: 1, height: 32, color: Colors.grey.shade200),

              // Increment Button
              _buildActionButton(
                icon: Icons.add,
                onPressed: widget.onIncrement,
                colour: primaryColor,
                borderRadius:
                    const BorderRadius.horizontal(right: Radius.circular(11)),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color colour,
    BorderRadius? borderRadius,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius ?? BorderRadius.zero,
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        child: SizedBox(
          width: 56,
          height: 18,
          child: Icon(
            icon,
            color: colour,
            size: 22,
          ),
        ),
      ),
    );
  }
}
