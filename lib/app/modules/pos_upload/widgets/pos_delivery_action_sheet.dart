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

/// Confirms a Stock Manager action that takes no driver (Revert to Pending,
/// Complete). Resolves `true` only on Confirm; dismissing sends nothing.
Future<bool?> showPosConfirmActionSheet(
  BuildContext context,
  PosDeliveryAction action,
) {
  final explanation = switch (action) {
    PosDeliveryAction.complete =>
      'The delivered POS Upload is closed as Completed. Its Delivery Note must '
          'still be submitted. No further delivery actions are possible.',
    _ =>
      'The POS Upload goes back to Pending so it can be edited or '
          're-imported. Saving its Delivery Note or Stock Entry moves it '
          'to In Progress again.',
  };
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: context.scheme.fg,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final scheme = sheetContext.scheme;
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                action.label,
                style: theme.textTheme.titleLarge?.copyWith(color: scheme.text),
              ),
              const SizedBox(height: 16),
              Text(
                explanation,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (ModalRoute.isCurrentOf(sheetContext) == true) {
                    Navigator.of(sheetContext).pop(true);
                  }
                },
                child: const Text('Confirm'),
              ),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).maybePop(),
                style: TextButton.styleFrom(foregroundColor: scheme.textMuted),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    },
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
