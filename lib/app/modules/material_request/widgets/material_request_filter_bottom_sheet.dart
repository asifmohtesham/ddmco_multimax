import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';

/// Filter bottom sheet for Material Request List View.
/// Mirrors StockEntryFilterBottomSheet — same look, same apply/clear pattern.
class MaterialRequestFilterBottomSheet extends StatefulWidget {
  const MaterialRequestFilterBottomSheet({super.key});

  @override
  State<MaterialRequestFilterBottomSheet> createState() =>
      _MaterialRequestFilterBottomSheetState();
}

class _MaterialRequestFilterBottomSheetState
    extends State<MaterialRequestFilterBottomSheet> {
  final MaterialRequestController controller =
      Get.find<MaterialRequestController>();

  String? _selectedStatus;
  String? _selectedType;

  static const _statuses = ['Draft', 'Submitted', 'Stopped', 'Cancelled'];
  static const _types = [
    'Purchase',
    'Material Transfer',
    'Material Issue',
    'Manufacture',
    'Customer Provided',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill from active filters
    _selectedStatus =
        controller.activeFilters['status']?.toString();
    _selectedType =
        controller.activeFilters['material_request_type']?.toString();
  }

  void _applyFilters() {
    final filters = Map<String, dynamic>.from(controller.activeFilters);
    if (_selectedStatus != null) {
      filters['status'] = _selectedStatus;
    } else {
      filters.remove('status');
    }
    if (_selectedType != null) {
      filters['material_request_type'] = _selectedType;
    } else {
      filters.remove('material_request_type');
    }
    controller.applyFilters(filters);
    Get.back();
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = null;
      _selectedType = null;
    });
    controller.clearFilters();
    Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Filter Requests',
                  style: theme.textTheme.titleLarge),
              IconButton(
                  onPressed: () => Get.back(),
                  icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 20),

          // ── Status ──────────────────────────────────────────────────
          Text('Status', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _statuses.map((s) {
              final selected = _selectedStatus == s;
              return FilterChip(
                label: Text(s),
                selected: selected,
                onSelected: (_) =>
                    setState(() => _selectedStatus = selected ? null : s),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // ── Request Type ─────────────────────────────────────────────
          Text('Request Type', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _types.map((t) {
              final selected = _selectedType == t;
              return FilterChip(
                label: Text(t),
                selected: selected,
                onSelected: (_) =>
                    setState(() => _selectedType = selected ? null : t),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // ── Buttons ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear All'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _applyFilters,
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
