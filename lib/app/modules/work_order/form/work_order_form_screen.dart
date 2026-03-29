import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/global_widgets/save_icon_button.dart';
import 'job_card_creation_sheet.dart';
import 'work_order_form_controller.dart';

class WorkOrderFormScreen extends GetView<WorkOrderFormController> {
  const WorkOrderFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (controller.isDirty.value) {
          await controller.confirmDiscard();
        } else {
          Get.back();
        }
      },
      child: Obx(() {
        final wo = controller.workOrder.value;
        final title =
            (wo?.name.isEmpty ?? true) || wo?.name == 'New Work Order'
                ? 'New Work Order'
                : wo!.name;
        return Scaffold(
          appBar: MainAppBar(
            title: title,
            status: wo?.status,
            onSave:     controller.canEdit ? controller.save : null,
            isSaving:   controller.isSaving.value,
            isDirty:    controller.isDirty.value,
            saveResult: SaveResult.idle,
          ),
          body: controller.isLoading.value
              ? const Center(child: CircularProgressIndicator())
              : _WorkOrderForm(controller: controller),
        );
      }),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Main form
// ────────────────────────────────────────────────────────────────────────────

class _WorkOrderForm extends StatelessWidget {
  final WorkOrderFormController controller;
  const _WorkOrderForm({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Obx(() {
      // Read the observable directly so GetX can track this Obx dependency.
      // Previously `controller.canEdit` (a plain getter) was used here, which
      // gave GetX nothing to track and caused an "improper use of Obx" crash.
      final wo      = controller.workOrder.value;
      final canEdit = wo?.docstatus == 0 || controller.mode == 'new';

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Section: Production ────────────────────────────────────────────
            _SectionHeader(
                label: 'Production Details',
                icon: Icons.precision_manufacturing_outlined),
            const SizedBox(height: 12),

            // Item search typeahead
            _FieldLabel(label: 'Production Item *'),
            const SizedBox(height: 6),
            Obx(() {
              final items = controller.itemOptions;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller.itemController,
                    readOnly: !canEdit,
                    decoration: InputDecoration(
                      hintText: 'Search item code…',
                      border: const OutlineInputBorder(),
                      filled: !canEdit,
                      fillColor:
                          !canEdit ? cs.surfaceContainerHighest : null,
                      prefixIcon: const Icon(Icons.inventory_2_outlined),
                      suffixIcon: controller.isFetchingItems.value
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          : (controller.itemController.text.isNotEmpty &&
                                  canEdit
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    controller.itemController.clear();
                                    controller.selectedItem.value = null;
                                    controller.selectedItemName.value = null;
                                    controller.bomController.clear();
                                    controller.selectedBom.value = null;
                                    controller.bomOptions.clear();
                                    controller.isItemValid.value = false;
                                    controller.isBomValid.value  = false;
                                  })
                              : null),
                    ),
                    onChanged: controller.searchItems,
                  ),
                  if (items.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Column(
                        children: items
                            .map((code) => ListTile(
                                  dense: true,
                                  title: Text(code),
                                  onTap: () =>
                                      controller.onItemSelected(code),
                                ))
                            .toList(),
                      ),
                    ),
                  if ((controller.selectedItemName.value ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        controller.selectedItemName.value!,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 16),

            // BOM No
            _FieldLabel(label: 'BOM No *'),
            const SizedBox(height: 6),
            Obx(() {
              final loadingBom = controller.isFetchingBom.value;
              return TextField(
                controller: controller.bomController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: loadingBom
                      ? 'Fetching BOM…'
                      : 'Auto-filled or tap to choose',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                  suffixIcon: loadingBom
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                        )
                      : (canEdit && controller.bomOptions.length > 1
                          ? IconButton(
                              icon: const Icon(
                                  Icons.arrow_drop_down_circle_outlined),
                              onPressed: controller.showBomPicker,
                            )
                          : null),
                ),
                onTap: canEdit && controller.bomOptions.length > 1
                    ? controller.showBomPicker
                    : null,
              );
            }),
            const SizedBox(height: 16),

            // Qty row with ± stepper
            _FieldLabel(label: 'Quantity *'),
            const SizedBox(height: 6),
            Row(
              children: [
                if (canEdit)
                  _StepButton(
                    icon: Icons.remove,
                    onTap: () => controller.adjustQty(-1),
                  ),
                Expanded(
                  child: TextField(
                    controller: controller.qtyController,
                    readOnly: !canEdit,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      filled: !canEdit,
                      fillColor:
                          !canEdit ? cs.surfaceContainerHighest : null,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 8),
                    ),
                  ),
                ),
                if (canEdit)
                  _StepButton(
                    icon: Icons.add,
                    onTap: () => controller.adjustQty(1),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Section: Dates ─────────────────────────────────────────────────
            _SectionHeader(
                label: 'Dates', icon: Icons.date_range_outlined),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: 'Planned Start *',
                    controller: controller.plannedStartController,
                    readOnly: !canEdit,
                    onTap: () => controller
                        .pickDate(controller.plannedStartController),
                    fillColor:
                        !canEdit ? cs.surfaceContainerHighest : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DateField(
                    label: 'Expected End',
                    controller: controller.expectedEndController,
                    readOnly: !canEdit,
                    onTap: () => controller
                        .pickDate(controller.expectedEndController),
                    fillColor:
                        !canEdit ? cs.surfaceContainerHighest : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Section: Warehouses ───────────────────────────────────────────
            _SectionHeader(
                label: 'Warehouses', icon: Icons.warehouse_outlined),
            const SizedBox(height: 12),

            _WarehouseField(
              label: 'WIP Warehouse',
              controller: controller.wipWarehouseController,
              readOnly: !canEdit,
              onTap: () => controller
                  .showWarehousePicker(controller.wipWarehouseController),
              fillColor: !canEdit ? cs.surfaceContainerHighest : null,
            ),
            const SizedBox(height: 12),

            _WarehouseField(
              label: 'FG Warehouse',
              controller: controller.fgWarehouseController,
              readOnly: !canEdit,
              onTap: () => controller
                  .showWarehousePicker(controller.fgWarehouseController),
              fillColor: !canEdit ? cs.surfaceContainerHighest : null,
            ),
            const SizedBox(height: 24),

            // ── Section: Notes ─────────────────────────────────────────────────
            _SectionHeader(
                label: 'Notes', icon: Icons.notes_outlined),
            const SizedBox(height: 12),

            TextField(
              controller: controller.descriptionController,
              readOnly: !canEdit,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add notes or description…',
                border: const OutlineInputBorder(),
                filled: !canEdit,
                fillColor:
                    !canEdit ? cs.surfaceContainerHighest : null,
                alignLabelWithHint: true,
              ),
              onChanged: (_) => controller.markDirty(),
            ),
            const SizedBox(height: 24),

            // ── Section: Operations ───────────────────────────────────────────
            Obx(() {
              if (controller.operations.isEmpty) return const SizedBox.shrink();
              return _OperationsSection(
                controller: controller,
                cs: cs,
                textTheme: textTheme,
              );
            }),

            // ── Action buttons (Save / Submit / Create Job Cards) ─────────────
            const SizedBox(height: 8),

            // Save button — shown when draft
            // Reads all relevant observables directly so GetX can track them
            // and reactively enable/disable the button without canSave getter.
            if (canEdit)
              Obx(() {
                final saving  = controller.isSaving.value;
                final canSave = controller.isDirty.value &&
                    controller.isItemValid.value &&
                    controller.isBomValid.value &&
                    controller.isQtyValid.value;
                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: canSave ? controller.save : null,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      saving
                          ? 'Saving…'
                          : controller.mode == 'new'
                              ? 'Create Work Order'
                              : 'Save Changes',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.all(16)),
                  ),
                );
              }),

            // Submit button — shown for saved drafts (docstatus 0, mode view)
            // Reads observables directly so GetX can track visibility changes
            // without relying on the plain canSubmit getter.
            Obx(() {
              final wo          = controller.workOrder.value;
              final submitting  = controller.isSubmitting.value;
              final canSubmit   = controller.mode != 'new' &&
                  wo?.docstatus == 0 &&
                  !controller.isSaving.value &&
                  !submitting;
              if (!canSubmit) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        submitting ? null : controller.submitWorkOrder,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      backgroundColor: cs.tertiary,
                      foregroundColor: cs.onTertiary,
                    ),
                    icon: submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      submitting ? 'Submitting…' : 'Submit Work Order',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              );
            }),

            // Create Job Cards button — shown when submitted + pending ops exist
            // Reads observables directly so GetX can track visibility changes
            // without relying on the plain canCreateJobCards getter.
            Obx(() {
              final wo              = controller.workOrder.value;
              final creatingCards   = controller.isCreatingJobCards.value;
              final woQty           = wo?.qty ?? 0;
              final hasPendingOps   = controller.operations.any(
                  (op) => op.pendingQty(woQty) > 0);
              final canCreateCards  = wo?.docstatus == 1 && hasPendingOps;
              if (!canCreateCards) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: creatingCards
                        ? null
                        : () => Get.bottomSheet(
                              JobCardCreationSheet(
                                  controller: controller),
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                            ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      side: BorderSide(color: cs.primary, width: 1.5),
                    ),
                    icon: creatingCards
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.primary))
                        : const Icon(Icons.playlist_add_check_outlined),
                    label: Text(
                      creatingCards
                          ? 'Creating Job Cards…'
                          : 'Create Job Cards',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      );
    });
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Operations section
// ────────────────────────────────────────────────────────────────────────────

class _OperationsSection extends StatelessWidget {
  final WorkOrderFormController controller;
  final ColorScheme   cs;
  final TextTheme     textTheme;
  const _OperationsSection({
    required this.controller,
    required this.cs,
    required this.textTheme,
  });

  Color _statusColor(String status) => switch (status) {
    WorkOrderOperationStatus.wip       => Colors.orange.shade700,
    WorkOrderOperationStatus.completed => cs.primary,
    _                                  => cs.onSurfaceVariant,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
            label: 'Operations',
            icon: Icons.account_tree_outlined),
        const SizedBox(height: 12),
        ...controller.operations.map((op) {
          final woQty     = controller.workOrder.value?.qty ?? 0;
          final pending   = op.pendingQty(woQty);
          final progress  = woQty > 0
              ? (op.completedQty / woQty).clamp(0.0, 1.0)
              : 0.0;
          final statusClr = _statusColor(op.status);

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: sequence badge + operation name + status chip
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${op.sequenceId}',
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        op.operation,
                        style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusClr.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        op.status,
                        style: textTheme.labelSmall?.copyWith(
                          color: statusClr,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                // Row 2: workstation (if set)
                if ((op.workstation ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.precision_manufacturing_outlined,
                          size: 12, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        op.workstation!,
                        style: textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: cs.outlineVariant,
                    color: statusClr,
                  ),
                ),

                const SizedBox(height: 4),

                // Completed / pending counts
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Completed: ${_fmtQty(op.completedQty)}',
                      style: textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    Text(
                      'Pending: ${_fmtQty(pending)}',
                      style: textTheme.labelSmall?.copyWith(
                        color: pending > 0
                            ? cs.error
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }

  String _fmtQty(double qty) =>
      qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(2);
}

/// Thin status constant shim used by [_OperationsSection._statusColor].
/// Mirrors the constants defined in [WorkOrderOperation] without adding
/// a dependency on the full model import here.
abstract class WorkOrderOperationStatus {
  static const String wip       = 'Work In Progress';
  static const String completed = 'Completed';
}

// ────────────────────────────────────────────────────────────────────────────
// Small widgets (unchanged from original)
// ────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
              color: cs.primary.withValues(alpha: 0.2), thickness: 1),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 44,
        height: 50,
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(8),
          color: cs.surfaceContainerHighest,
        ),
        child: Icon(icon, color: cs.primary),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool readOnly;
  final VoidCallback onTap;
  final Color? fillColor;
  const _DateField({
    required this.label,
    required this.controller,
    required this.readOnly,
    required this.onTap,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: readOnly ? null : onTap,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: fillColor != null,
        fillColor: fillColor,
        suffixIcon: Icon(
          Icons.calendar_today_outlined,
          size: 18,
          color: readOnly
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _WarehouseField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool readOnly;
  final VoidCallback onTap;
  final Color? fillColor;
  const _WarehouseField({
    required this.label,
    required this.controller,
    required this.readOnly,
    required this.onTap,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: readOnly ? null : onTap,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: fillColor ?? cs.surfaceContainerLowest,
        prefixIcon: const Icon(Icons.warehouse_outlined),
        suffixIcon: readOnly
            ? null
            : Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
      ),
    );
  }
}
