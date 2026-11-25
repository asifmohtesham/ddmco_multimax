import 'dart:async';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

import 'suppliers_by_item_controller.dart';
import 'suppliers_by_item_fields.dart';
import 'suppliers_by_item_layout.dart';

String suppliersByItemGroupLabel(SuppliersByItemGroup group) => switch (group) {
  SuppliersByItemGroup.template => 'Item',
  SuppliersByItemGroup.supplier => 'Supplier',
};

String suppliersByItemSortLabel(
  SuppliersByItemSortField field, [
  String Function(SuppliersByItemField)? label,
]) {
  final selected = switch (field) {
    SuppliersByItemSortField.stock => SuppliersByItemField.itemBalance,
    SuppliersByItemSortField.supplierCount =>
      SuppliersByItemField.itemSupplierCount,
    SuppliersByItemSortField.lastPurchase =>
      SuppliersByItemField.supplierLastPurchase,
  };
  return label?.call(selected) ?? selected.label;
}

String suppliersByItemDirectionLabel(
  SuppliersByItemSortField field,
  SuppliersByItemSortDirection direction,
) => switch ((field, direction)) {
  (SuppliersByItemSortField.lastPurchase, SuppliersByItemSortDirection.asc) =>
    'Oldest first',
  (SuppliersByItemSortField.lastPurchase, SuppliersByItemSortDirection.desc) =>
    'Newest first',
  (_, SuppliersByItemSortDirection.asc) => 'Low to high',
  (_, SuppliersByItemSortDirection.desc) => 'High to low',
};

Future<void> showSuppliersByItemView(
  BuildContext context,
  SuppliersByItemController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: context.scheme.fg,
  builder: (context) => _ViewSheet(controller: controller),
);

class _ViewSheet extends StatelessWidget {
  const _ViewSheet({required this.controller});

  final SuppliersByItemController controller;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Semantics(
              header: true,
              child: Text(
                'View',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Obx(() {
                final view = controller.view.value;
                final editable = controller.viewEditable;
                final visibility = controller.fieldVisibility;
                final displayEditable =
                    controller.fieldsEditable &&
                    !controller.viewDisplayResetting.value;
                final canExpand = controller.canExpandAll;
                final canCollapse = controller.canCollapseAll;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ViewOptions(
                      title: 'Group by',
                      values: SuppliersByItemGroup.values,
                      selection: view.group,
                      label: suppliersByItemGroupLabel,
                      onChanged: editable ? controller.setGroup : null,
                    ),
                    _ViewOptions(
                      title: 'Sort',
                      values: SuppliersByItemSortField.values,
                      selection: view.sortField,
                      label: (value) => suppliersByItemSortLabel(
                        value,
                        controller.fieldLabel,
                      ),
                      onChanged: editable ? controller.setSortField : null,
                    ),
                    _ViewOptions(
                      title: 'Direction',
                      values: SuppliersByItemSortDirection.values,
                      selection: view.sortDirection,
                      label: (value) =>
                          suppliersByItemDirectionLabel(view.sortField, value),
                      onChanged: editable ? controller.setSortDirection : null,
                    ),
                    ListTile(
                      minTileHeight: 48,
                      leading: const Icon(Icons.unfold_more),
                      title: const Text('Expand all'),
                      enabled: canExpand,
                      onTap: canExpand
                          ? () {
                              controller.expandAll();
                              Navigator.of(context).pop();
                            }
                          : null,
                    ),
                    ListTile(
                      minTileHeight: 48,
                      leading: const Icon(Icons.unfold_less),
                      title: const Text('Collapse all'),
                      enabled: canCollapse,
                      onTap: canCollapse
                          ? () {
                              controller.collapseAll();
                              Navigator.of(context).pop();
                            }
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        12,
                        8,
                        12,
                        4,
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Semantics(
                            header: true,
                            child: const Text('Display options'),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed: displayEditable
                                ? () => unawaited(
                                    controller.resetViewDisplayOptions(),
                                  )
                                : null,
                            child: const Text('Reset display options'),
                          ),
                        ],
                      ),
                    ),
                    for (final field in SuppliersByItemField.values)
                      if (field.movedToView)
                        CheckboxListTile(
                          key: ValueKey(field),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            field == SuppliersByItemField.summaryStockByUom
                                ? controller.fieldLabel(
                                    SuppliersByItemField.itemBalance,
                                  )
                                : field.label,
                          ),
                          subtitle: field.qualifier == null
                              ? null
                              : Text(field.qualifier!),
                          value: visibility.shows(field),
                          minTileHeight: 48,
                          onChanged:
                              displayEditable &&
                                  !controller.isSavingField(field)
                              ? (value) => unawaited(
                                  controller.setFieldVisible(field, value!),
                                )
                              : null,
                        ),
                  ],
                );
              }),
            ),
          ),
          SuppliersByItemViewFeedback(
            controller: controller,
            showSessionStatus: true,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ViewOptions<T extends Enum> extends StatelessWidget {
  const _ViewOptions({
    required this.title,
    required this.values,
    required this.selection,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final List<T> values;
  final T selection;
  final String Function(T) label;
  final Future<void> Function(T)? onChanged;

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
    groupValue: selection,
    onChanged: (value) {
      final change = onChanged;
      if (change != null && value != null && value != selection) {
        unawaited(change(value));
      }
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(color: context.scheme.textMuted),
            ),
          ),
        ),
        for (final value in values)
          RadioListTile<T>(
            key: ValueKey(value),
            value: value,
            enabled: onChanged != null,
            minTileHeight: 48,
            title: Text(label(value)),
          ),
      ],
    ),
  );
}

class SuppliersByItemViewFeedback extends StatelessWidget {
  const SuppliersByItemViewFeedback({
    super.key,
    required this.controller,
    this.showSessionStatus = false,
  });

  final SuppliersByItemController controller;
  final bool showSessionStatus;

  @override
  Widget build(BuildContext context) => Obx(() {
    final viewError =
        (showSessionStatus ? controller.settingsScopeLoadError.value : null) ??
        controller.viewLoadError.value ??
        controller.viewSaveError.value;
    final displayError = !showSessionStatus
        ? null
        : controller.fieldsLoadError.value ?? controller.fieldsSaveError.value;
    final error = viewError ?? displayError;
    final loading = controller.fieldsScopeLoading.value;
    final busy =
        loading ||
        controller.viewSaving.value ||
        controller.viewRetrying.value ||
        (showSessionStatus &&
            (controller.fieldsSaving.value || controller.fieldsRetrying.value));
    final message =
        error ??
        (!showSessionStatus
            ? null
            : loading
            ? 'Loading settings…'
            : busy
            ? 'Saving View…'
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
                  : () => unawaited(
                      viewError == null
                          ? controller.retryFields()
                          : controller.retryView(),
                    ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  });
}
