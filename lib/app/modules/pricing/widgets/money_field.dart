import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// Rejects any edit that would leave more than one decimal point (and any
/// non-digit/non-dot character), so a slipped double-tap like '12..5' or
/// '1.2.3' can never parse to 0 on save.
final TextInputFormatter decimalInputFormatter =
    TextInputFormatter.withFunction((oldValue, newValue) =>
        RegExp(r'^\d*\.?\d*$').hasMatch(newValue.text) ? newValue : oldValue);

/// Large tabular numeric input with an optional currency prefix and unit
/// suffix (DESIGN_SPEC "MoneyField"). Reformats to [decimals] places on blur;
/// pass `decimals: null` for percentages.
class MoneyField extends StatefulWidget {
  const MoneyField({
    super.key,
    required this.label,
    required this.controller,
    this.prefix,
    this.suffix,
    this.readOnly = false,
    this.errorText,
    this.decimals = 2,
  });

  final String label;
  final TextEditingController controller;
  final String? prefix;
  final String? suffix;
  final bool readOnly;
  final String? errorText;
  final int? decimals;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (!_focus.hasFocus) _format();
    setState(() {});
  }

  void _format() {
    final d = widget.decimals;
    if (d == null || widget.readOnly) return;
    final v = double.tryParse(widget.controller.text.replaceAll(',', ''));
    if (v == null) return;
    final text = v.toStringAsFixed(d);
    if (text != widget.controller.text) widget.controller.text = text;
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final focused = _focus.hasFocus && !widget.readOnly;
    final hasError = widget.errorText != null;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: widget.readOnly ? s.subtle : s.fg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasError
                  ? AppColors.red500
                  : focused
                      ? s.primary
                      : (widget.readOnly ? s.border : s.borderStrong),
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                        color: s.primary.withValues(alpha: 0.22),
                        spreadRadius: 3)
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.label,
                  style: TextStyle(fontSize: 10, color: s.textMuted)),
              Row(
                children: [
                  if (widget.prefix != null) ...[
                    Text(widget.prefix!,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: s.textMuted)),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focus,
                      readOnly: widget.readOnly,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [decimalInputFormatter],
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: s.text,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (widget.suffix != null) ...[
                    const SizedBox(width: 6),
                    Text(widget.suffix!,
                        style: TextStyle(fontSize: 13, color: s.textMuted)),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(widget.errorText!,
                style: TextStyle(
                    fontSize: 11,
                    color: dark ? AppColors.red300 : AppColors.red700)),
          ),
      ],
    );
  }
}

/// Inline field error line used under DocPickerFields (which have no error
/// slot). Renders nothing for a null message.
class FieldErrorText extends StatelessWidget {
  const FieldErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? AppColors.red300 : AppColors.red700;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 13, color: ink),
          const SizedBox(width: 5),
          Expanded(
            child: Text(message!, style: TextStyle(fontSize: 11, color: ink)),
          ),
        ],
      ),
    );
  }
}
