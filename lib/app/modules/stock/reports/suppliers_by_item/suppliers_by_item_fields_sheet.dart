import 'dart:async';

// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_controller.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_fields.dart';

Future<void> showSuppliersByItemFields(
  BuildContext context,
  SuppliersByItemController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  backgroundColor: context.scheme.fg,
  builder: (_) => _FieldsSheet(controller: controller),
);

class _FieldsSheet extends StatelessWidget {
  const _FieldsSheet({required this.controller});

  final SuppliersByItemController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Obx(() {
        final visibility = controller.fieldVisibility;
        final showsRate = visibility.shows(SuppliersByItemField.supplierRate);
        final editable = controller.fieldsEditable;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fields',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: editable && !controller.fieldsResetting.value
                        ? () => unawaited(controller.resetFields())
                        : null,
                    child: const Text('Reset to defaults'),
                  ),
                ],
              ),
            ),
            SuppliersByItemFieldsFeedback(
              controller: controller,
              showSessionStatus: true,
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: EdgeInsets.only(
                  bottom: 16 + MediaQuery.viewPaddingOf(context).bottom,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                      'Item / Supplier, No supplier recorded, navigation '
                      'and footer totals always show.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: context.scheme.textMuted,
                      ),
                    ),
                  ),
                  for (final group in SuppliersByItemFieldGroup.values) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Semantics(
                        header: true,
                        child: Text(
                          group.label,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ),
                    for (final field in SuppliersByItemField.values.where(
                      (field) => field.group == group,
                    ))
                      _fieldTile(field, visibility, showsRate, editable),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _fieldTile(
    SuppliersByItemField field,
    SuppliersByItemFieldVisibility visibility,
    bool showsRate,
    bool editable,
  ) {
    final needsRate =
        !showsRate &&
        (field == SuppliersByItemField.supplierRateCurrency ||
            field == SuppliersByItemField.supplierRateUom);
    final enabled = editable && !needsRate && !controller.isSavingField(field);
    return CheckboxListTile(
      key: ValueKey(field),
      minTileHeight: 48,
      controlAffinity: ListTileControlAffinity.leading,
      title: Semantics(
        label: '${field.group.label}, ${field.label}',
        excludeSemantics: true,
        child: Text(field.label),
      ),
      subtitle: needsRate
          ? Text('Needs ${SuppliersByItemField.supplierRate.label}')
          : field.qualifier == null
          ? null
          : Text(field.qualifier!),
      value: visibility.shows(field),
      onChanged: enabled
          ? (value) => unawaited(controller.setFieldVisible(field, value!))
          : null,
    );
  }
}

/// Preference feedback stays visible even when the sheet's checkbox list scrolls.
class SuppliersByItemFieldsFeedback extends StatelessWidget {
  const SuppliersByItemFieldsFeedback({
    super.key,
    required this.controller,
    this.showSessionStatus = false,
  });

  final SuppliersByItemController controller;
  final bool showSessionStatus;

  @override
  Widget build(BuildContext context) => Obx(() {
    final error =
        (showSessionStatus ? controller.settingsScopeLoadError.value : null) ??
        controller.fieldsLoadError.value ??
        controller.fieldsSaveError.value;
    final busy =
        controller.fieldsScopeLoading.value ||
        controller.fieldsSaving.value ||
        controller.fieldsRetrying.value;
    final message =
        error ??
        (!showSessionStatus
            ? null
            : controller.fieldsScopeLoading.value
            ? 'Loading settings…'
            : busy
            ? 'Saving Fields…'
            : controller.fieldsSessionOnly.value
            ? 'Settings apply to this session'
            : null);
    if (message == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
      child: Row(
        children: [
          if (busy) ...[
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.scheme.textMuted,
                ),
              ),
            ),
          ),
          if (error != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: busy
                  ? null
                  : () => unawaited(controller.retryFields()),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  });
}
