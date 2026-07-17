import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';
import 'package:multimax/app/modules/item/form/reorder_rules.dart';

/// Bottom-sheet editor for a single `Item.reorder_levels` row.
///
/// The Desk grid is five columns wide and has no mobile equivalent, so each
/// row is edited in its own sheet.
///
/// Link filters mirror erpnext item.js:449-473 — "Check in (group)" lists
/// group warehouses, "Request for" lists leaf warehouses. v15 *intends* to
/// narrow "Request for" to children of the chosen group but that branch is
/// dead upstream (`Item Reorder` has no `parent_warehouse` field, and
/// `filters.extend` is Python idiom that would throw in JS), so Desk lists
/// every leaf warehouse company-wide and so do we. A mismatched pair is caught
/// by the server's descendant check on save.
class ReorderRuleSheet extends StatefulWidget {
  const ReorderRuleSheet({
    super.key,
    required this.initial,
    required this.loadWarehouses,
    required this.onSaved,
  });

  final ItemReorder initial;

  /// Injected so the sheet needs no provider and stays pumpable in tests.
  final Future<List<String>> Function({required bool isGroup}) loadWarehouses;

  final ValueChanged<ItemReorder> onSaved;

  @override
  State<ReorderRuleSheet> createState() => _ReorderRuleSheetState();
}

class _ReorderRuleSheetState extends State<ReorderRuleSheet> {
  late String? _warehouseGroup;
  late String _warehouse;
  late String _type;

  late final TextEditingController _levelCtrl;
  late final TextEditingController _qtyCtrl;

  bool _loadingWarehouses = false;

  @override
  void initState() {
    super.initState();
    _warehouseGroup = widget.initial.warehouseGroup;
    _warehouse = widget.initial.warehouse;
    _type = widget.initial.materialRequestType;
    _levelCtrl =
        TextEditingController(text: _initialNum(widget.initial.warehouseReorderLevel));
    _qtyCtrl =
        TextEditingController(text: _initialNum(widget.initial.warehouseReorderQty));
  }

  /// Zero renders blank so the field reads as "unset" rather than "0".
  ///
  /// Uses formatQty, not formatQtyGrouped: this seeds an editable numeric
  /// field, and thousands separators would not survive double.tryParse.
  String _initialNum(double v) => v == 0 ? '' : FormattingHelper.formatQty(v);

  @override
  void dispose() {
    _levelCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickWarehouse({required bool isGroup}) async {
    if (_loadingWarehouses) return;
    setState(() => _loadingWarehouses = true);
    try {
      final warehouses = await widget.loadWarehouses(isGroup: isGroup);
      if (!mounted) return;

      Get.bottomSheet(
        WarehousePickerSheet(
          warehouses: warehouses,
          isLoading: false,
          title: isGroup ? 'Select group warehouse' : 'Select warehouse',
          groupNames: isGroup ? warehouses.toSet() : const {},
          onSelected: (wh) => setState(() {
            if (isGroup) {
              _warehouseGroup = wh;
            } else {
              _warehouse = wh;
            }
          }),
        ),
        isScrollControlled: true,
      );
    } finally {
      if (mounted) setState(() => _loadingWarehouses = false);
    }
  }

  void _pickType() {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Material Request Type',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...kReorderMaterialRequestTypes.map(
              (t) => ListTile(
                title: Text(t),
                trailing: t == _type ? const Icon(Icons.check) : null,
                onTap: () {
                  // Navigator.of(ctx).pop() rather than Get.back(): Get.back()
                  // calls closeCurrentSnackbar first, which throws when a
                  // Snackbar is queued but not yet attached to the Overlay.
                  Navigator.of(context).pop();
                  setState(() => _type = t);
                },
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  void _save() {
    widget.onSaved(widget.initial.copyWith(
      warehouseGroup: _warehouseGroup,
      clearWarehouseGroup: _warehouseGroup == null,
      warehouse: _warehouse,
      materialRequestType: _type,
      warehouseReorderLevel: double.tryParse(_levelCtrl.text.trim()) ?? 0,
      warehouseReorderQty: double.tryParse(_qtyCtrl.text.trim()) ?? 0,
    ));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      // Lifts the sheet above the keyboard when the numeric fields focus.
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(
                  'Re-order rule',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: scheme.text,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DocPickerField(
                label: 'Check in (group)',
                icon: Icons.account_tree_outlined,
                value: _warehouseGroup,
                placeholder: 'Same as Request for',
                helperText: 'Where stock is measured',
                trailingIcon: Icons.chevron_right,
                onTap: _loadingWarehouses
                    ? null
                    : () => _pickWarehouse(isGroup: true),
              ),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Request for',
                icon: Icons.warehouse_outlined,
                value: _warehouse.isEmpty ? null : _warehouse,
                placeholder: 'Select warehouse',
                helperText: 'Where the Material Request is raised',
                trailingIcon: Icons.chevron_right,
                onTap: _loadingWarehouses
                    ? null
                    : () => _pickWarehouse(isGroup: false),
              ),
              const SizedBox(height: 12),
              _numberField(context, 'Re-order Level', _levelCtrl),
              const SizedBox(height: 12),
              _numberField(context, 'Re-order Qty', _qtyCtrl),
              const SizedBox(height: 12),
              DocPickerField(
                label: 'Material Request Type',
                icon: Icons.playlist_add_check,
                value: _type.isEmpty ? null : _type,
                placeholder: 'Select type',
                trailingIcon: Icons.chevron_right,
                onTap: _pickType,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Done'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberField(
      BuildContext context, String label, TextEditingController ctrl) {
    final scheme = context.scheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: scheme.textMuted)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
          ],
          style: TextStyle(color: scheme.text),
          decoration: InputDecoration(
            hintText: '0',
            filled: true,
            fillColor: scheme.subtle,
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }
}
