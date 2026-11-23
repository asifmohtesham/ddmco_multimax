// Keep the app's shared Material APIs until its Material migration.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/warehouse_picker_sheet.dart';

import '../rack_warehouse_resolver.dart';
import '../rack_warehouse_rule.dart';

/// Acknowledgements belong to the active document controller.
class WarehouseDivergenceConfirmation {
  final isPending = false.obs;
  final _acknowledged = <String>{};

  Future<bool> confirm(Iterable<WarehouseDivergence> differences) async {
    if (isPending.value) return false;
    final pending = differences
        .where((difference) => !_acknowledged.contains(difference.key))
        .where((difference) => difference.messages.isNotEmpty)
        .toList();
    if (pending.isEmpty) return true;
    final context = Get.overlayContext ?? Get.context;
    if (context == null) return false;
    isPending.value = true;
    try {
      final keep = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Warehouse differs'),
          content: SingleChildScrollView(
            child: Text(
              pending.expand((difference) => difference.messages).join('\n\n'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Review row'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Keep warehouse'),
            ),
          ],
        ),
      );
      if (keep != true) return false;
      _acknowledged.addAll(pending.map((difference) => difference.key));
      return true;
    } finally {
      isPending.value = false;
    }
  }
}

class RowWarehouseField extends StatefulWidget {
  const RowWarehouseField({
    super.key,
    required this.label,
    required this.value,
    required this.company,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final String company;
  final ValueChanged<String> onChanged;

  @override
  State<RowWarehouseField> createState() => _RowWarehouseFieldState();
}

class _RowWarehouseFieldState extends State<RowWarehouseField> {
  bool _loading = false;

  Future<void> _pick() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final warehouses = await RackWarehouseResolver(
        Get.find<ApiProvider>(),
      ).activeWarehouses(widget.company);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => WarehousePickerSheet(
          warehouses: warehouses.map((warehouse) => warehouse.name).toList(),
          isLoading: false,
          onSelected: widget.onChanged,
          title: 'Select ${widget.label}',
        ),
      );
    } catch (_) {
      if (mounted) {
        GlobalSnackbar.warning(message: 'Could not load warehouses. Retry.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      dense: true,
      title: Text(widget.label),
      subtitle: Text(warehouseValue(widget.value) ?? 'Select warehouse'),
      trailing: _loading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.arrow_drop_down),
      onTap: _loading ? null : _pick,
    ),
  );
}

class RackWarehouseActions extends StatelessWidget {
  const RackWarehouseActions({
    super.key,
    required this.verdict,
    this.onChooseRack,
    this.onUseRackWarehouse,
    this.onRetry,
  });

  final RackPairVerdict? verdict;
  final VoidCallback? onChooseRack;
  final VoidCallback? onUseRackWarehouse;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final issue = verdict?.issue;
    if (issue == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      children: [
        if (onChooseRack != null && issue != RackPairIssue.inapplicable)
          TextButton(
            onPressed: onChooseRack,
            child: const Text('Choose another rack'),
          ),
        if (issue == RackPairIssue.mismatch && onUseRackWarehouse != null)
          TextButton(
            onPressed: onUseRackWarehouse,
            child: const Text('Use rack warehouse'),
          ),
        if (issue == RackPairIssue.unavailable && onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
