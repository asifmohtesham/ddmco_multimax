import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/work_order_operation_model.dart';
import 'package:multimax/app/modules/work_order/form/work_order_form_controller.dart';

/// Bottom sheet for selecting Work Order Operations to create Job Cards for.
///
/// Opened by the "Create Job Cards" action button on the Work Order form.
/// Receives [controller] to read [operations] and call [createJobCards].
///
/// Usage:
/// ```dart
/// Get.bottomSheet(
///   JobCardCreationSheet(controller: controller),
///   isScrollControlled: true,
/// );
/// ```
class JobCardCreationSheet extends StatefulWidget {
  final WorkOrderFormController controller;
  const JobCardCreationSheet({super.key, required this.controller});

  @override
  State<JobCardCreationSheet> createState() => _JobCardCreationSheetState();
}

class _JobCardCreationSheetState extends State<JobCardCreationSheet> {
  // Selection state
  final Set<String> _selected = {}; // WorkOrderOperation.name

  // qty controllers: op.name -> TextEditingController
  final Map<String, TextEditingController> _qtyControllers = {};

  // Per-row error messages (null = valid)
  final Map<String, String?> _qtyErrors = {};

  WorkOrderFormController get _c => widget.controller;

  List<WorkOrderOperation> get _eligibleOps => _c.operations
      .where((op) =>
          !op.isCompleted &&
          op.pendingQty(_c.workOrder.value!.qty) > 0)
      .toList()
    ..sort((a, b) => a.sequenceId.compareTo(b.sequenceId));

  @override
  void initState() {
    super.initState();
    final woQty = _c.workOrder.value!.qty;
    for (final op in _eligibleOps) {
      final pending = op.pendingQty(woQty);
      final initial = pending % 1 == 0
          ? pending.toInt().toString()
          : pending.toStringAsFixed(2);
      _qtyControllers[op.name] = TextEditingController(text: initial);
      _selected.add(op.name); // pre-select all eligible by default
      _qtyErrors[op.name] = null;
    }
  }

  @override
  void dispose() {
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Validation ──────────────────────────────────────────────────────────────

  bool _validateQty(WorkOrderOperation op, String value) {
    final woQty   = _c.workOrder.value!.qty;
    final pending = op.pendingQty(woQty);
    final entered = double.tryParse(value);
    String? error;
    if (entered == null || entered <= 0) {
      error = 'Must be > 0';
    } else if (entered > pending) {
      error = 'Max ${_formatQty(pending)}';
    }
    setState(() => _qtyErrors[op.name] = error);
    return error == null;
  }

  bool get _hasErrors =>
      _selected.any((name) => _qtyErrors[name] != null);

  bool get _canConfirm =>
      _selected.isNotEmpty && !_hasErrors && !_c.isCreatingJobCards.value;

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _formatQty(double qty) =>
      qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(2);

  Color _statusColor(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    return switch (status) {
      WorkOrderOperation.statusWip       => Colors.orange.shade700,
      WorkOrderOperation.statusCompleted => cs.primary,
      _                                  => cs.onSurfaceVariant,
    };
  }

  // ── Select all / none ────────────────────────────────────────────────────────

  void _toggleAll(bool? check) {
    setState(() {
      if (check == true) {
        _selected.addAll(_eligibleOps.map((e) => e.name));
      } else {
        _selected.clear();
      }
    });
  }

  // ── Confirm ──────────────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    // Validate all selected rows before submitting.
    bool allValid = true;
    for (final op in _eligibleOps.where((o) => _selected.contains(o.name))) {
      final val = _qtyControllers[op.name]?.text ?? '';
      if (!_validateQty(op, val)) allValid = false;
    }
    if (!allValid) return;

    final selected = _eligibleOps
        .where((op) => _selected.contains(op.name))
        .toList();
    final qtys = {
      for (final op in selected)
        op.name: double.tryParse(
                    _qtyControllers[op.name]?.text ?? '0') ??
                op.pendingQty(_c.workOrder.value!.qty),
    };

    Get.back();
    await _c.createJobCards(selected, qtys);
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final ops       = _eligibleOps;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize:     0.35,
      maxChildSize:     0.90,
      expand:           false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // ── Drag handle ──────────────────────────────────────────────
              _DragHandle(),

              // ── Header ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Icon(Icons.playlist_add_check_outlined,
                        size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Create Job Cards',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    // Select-all checkbox
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('All',
                            style: textTheme.labelMedium
                                ?.copyWith(color: cs.onSurfaceVariant)),
                        Checkbox(
                          tristate: true,
                          value: _selected.isEmpty
                              ? false
                              : _selected.length == ops.length
                                  ? true
                                  : null,
                          onChanged: _toggleAll,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Divider(
                  height: 1,
                  color: cs.outlineVariant,
                  indent: 16,
                  endIndent: 16),

              // ── Operations list ────────────────────────────────────────────
              Expanded(
                child: ops.isEmpty
                    ? Center(
                        child: Text(
                          'No pending operations',
                          style: textTheme.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: ops.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, i) =>
                            _OperationRow(
                          op:              ops[i],
                          woQty:           _c.workOrder.value!.qty,
                          isSelected:      _selected.contains(ops[i].name),
                          qtyController:   _qtyControllers[ops[i].name]!,
                          qtyError:        _qtyErrors[ops[i].name],
                          statusColor:     _statusColor(context, ops[i].status),
                          onToggle: (val) {
                            setState(() {
                              if (val == true) {
                                _selected.add(ops[i].name);
                              } else {
                                _selected.remove(ops[i].name);
                              }
                            });
                          },
                          onQtyChanged: (val) => _validateQty(ops[i], val),
                        ),
                      ),
              ),

              // ── Footer ──────────────────────────────────────────────────────
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Obx(() {
                    final loading = _c.isCreatingJobCards.value;
                    final n       = _selected.length;
                    return SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _canConfirm ? _confirm : null,
                        icon: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          loading
                              ? 'Creating…'
                              : n == 0
                                  ? 'Select operations'
                                  : 'Create $n Job Card${n == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 15),
                        ),
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(14)),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Operation row widget
// ────────────────────────────────────────────────────────────────────────────

class _OperationRow extends StatelessWidget {
  final WorkOrderOperation op;
  final double            woQty;
  final bool              isSelected;
  final TextEditingController qtyController;
  final String?           qtyError;
  final Color             statusColor;
  final ValueChanged<bool?> onToggle;
  final ValueChanged<String> onQtyChanged;

  const _OperationRow({
    required this.op,
    required this.woQty,
    required this.isSelected,
    required this.qtyController,
    required this.qtyError,
    required this.statusColor,
    required this.onToggle,
    required this.onQtyChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final pending   = op.pendingQty(woQty);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primaryContainer.withValues(alpha: 0.35)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: () => onToggle(!isSelected),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox
              Checkbox(
                value: isSelected,
                onChanged: onToggle,
                visualDensity: VisualDensity.compact,
              ),

              const SizedBox(width: 4),

              // Operation info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sequence + name
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
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Workstation + status chip
                    Row(
                      children: [
                        if ((op.workstation ?? '').isNotEmpty) ...[
                          Icon(Icons.precision_manufacturing_outlined,
                              size: 12,
                              color: cs.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              op.workstation!,
                              style: textTheme.labelSmall?.copyWith(
                                  color: cs.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            op.status,
                            style: textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // Pending qty label
                    Text(
                      'Pending: ${_formatQty(pending)} / ${_formatQty(woQty)}',
                      style: textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Qty input (only active when row is selected)
              SizedBox(
                width: 80,
                child: TextField(
                  controller: qtyController,
                  enabled:    isSelected,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d*')),
                  ],
                  onChanged: onQtyChanged,
                  decoration: InputDecoration(
                    labelText: 'Qty',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    errorText:  qtyError,
                    errorStyle: const TextStyle(fontSize: 9),
                    filled:     !isSelected,
                    fillColor:  cs.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatQty(double qty) =>
      qty % 1 == 0 ? qty.toInt().toString() : qty.toStringAsFixed(2);
}

// ────────────────────────────────────────────────────────────────────────────
// Drag handle
// ────────────────────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
