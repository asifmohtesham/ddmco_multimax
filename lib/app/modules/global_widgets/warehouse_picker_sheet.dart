import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A reusable warehouse-picker bottom sheet.
///
/// Usage (from any form controller):
///
/// ```dart
/// Get.bottomSheet(
///   WarehousePickerSheet(
///     warehouses: warehouses,
///     isLoading: isFetchingWarehouses,
///     onSelected: (wh) { controller.text = wh; },
///   ),
///   isScrollControlled: true,
/// );
/// ```
class WarehousePickerSheet extends StatefulWidget {
  const WarehousePickerSheet({
    super.key,
    required this.warehouses,
    required this.isLoading,
    required this.onSelected,
    this.title = 'Select Warehouse',
  });

  final List<String> warehouses;
  final bool isLoading;
  final ValueChanged<String> onSelected;
  final String title;

  @override
  State<WarehousePickerSheet> createState() => _WarehousePickerSheetState();
}

class _WarehousePickerSheetState extends State<WarehousePickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  late List<String> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = List<String>.from(widget.warehouses);
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List<String>.from(widget.warehouses)
          : widget.warehouses
              .where((w) => w.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: Get.height * 0.7,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Search...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('No warehouses found'))
                    : ListView.separated(
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final wh = _filtered[i];
                          return ListTile(
                            title: Text(wh),
                            onTap: () {
                              Get.back();
                              widget.onSelected(wh);
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
