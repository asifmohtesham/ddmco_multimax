import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pos_upload_delivery.dart';

Future<PosDeliverySelection?> showPosDeliveryActionSheet(
  BuildContext context,
  PosDeliveryAction action,
  PosDeliveryDriverOptions options,
) {
  return showModalBottomSheet<PosDeliverySelection>(
    context: context,
    backgroundColor: context.scheme.fg,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _PosDeliveryActionSheet(action: action, options: options),
  );
}

class _PosDeliveryActionSheet extends StatefulWidget {
  final PosDeliveryAction action;
  final PosDeliveryDriverOptions options;

  const _PosDeliveryActionSheet({required this.action, required this.options});

  @override
  State<_PosDeliveryActionSheet> createState() =>
      _PosDeliveryActionSheetState();
}

class _PosDeliveryActionSheetState extends State<_PosDeliveryActionSheet> {
  String? _driver;
  PosDeliveryReason? _reason;

  @override
  void initState() {
    super.initState();
    final defaultDriver = widget.options.defaultDriver;
    if (widget.options.drivers.any((driver) => driver.name == defaultDriver)) {
      _driver = defaultDriver;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = context.scheme;
    final drivers = widget.options.drivers;
    final fieldText = theme.textTheme.bodyLarge?.copyWith(color: scheme.text);

    InputDecoration fieldDecoration(String label) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: scheme.textMuted),
      border: const OutlineInputBorder(),
      filled: true,
      fillColor: scheme.subtle,
    );

    final driver = _driver;
    final canSubmit =
        driver != null && (!widget.action.requiresReason || _reason != null);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.action.label,
              style: theme.textTheme.titleLarge?.copyWith(color: scheme.text),
            ),
            const SizedBox(height: 16),
            if (drivers.isEmpty)
              Text(
                'No active drivers available',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.textMuted,
                ),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: driver,
                isExpanded: true,
                dropdownColor: scheme.fg,
                style: fieldText,
                decoration: fieldDecoration('Driver'),
                items: [
                  for (final option in drivers)
                    DropdownMenuItem(
                      value: option.name,
                      child: Text(
                        option.fullName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _driver = value),
              ),
            if (widget.action.requiresReason && drivers.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<PosDeliveryReason>(
                isExpanded: true,
                dropdownColor: scheme.fg,
                style: fieldText,
                decoration: fieldDecoration('Return Reason'),
                items: [
                  for (final reason in PosDeliveryReason.values)
                    DropdownMenuItem(value: reason, child: Text(reason.label)),
                ],
                onChanged: (value) => setState(() => _reason = value),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: canSubmit
                  ? () {
                      if (ModalRoute.isCurrentOf(context) == true) {
                        Navigator.of(context).pop(
                          PosDeliverySelection(driver: driver, reason: _reason),
                        );
                      }
                    }
                  : null,
              child: const Text('Confirm'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(foregroundColor: scheme.textMuted),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
