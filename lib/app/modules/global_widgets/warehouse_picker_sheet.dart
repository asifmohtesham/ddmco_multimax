import 'package:flutter/material.dart';

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
    this.groupNames = const {},
  });

  final List<String> warehouses;
  final bool isLoading;
  final ValueChanged<String> onSelected;
  final String title;
  final Set<String> groupNames;

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

  Widget _groupTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Group',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(16)),
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
                    : Material(
                        color: Colors.transparent,
                        child: ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final wh = _filtered[i];
                            final isGroup = widget.groupNames.contains(wh);
                            return ListTile(
                              title: Text(wh),
                              trailing: isGroup ? _groupTag(ctx) : null,
                              onTap: () {
                                // Use Navigator.of(ctx).pop() instead of Get.back().
                                // Get.back() unconditionally calls
                                // Get.closeCurrentSnackbar() before popping; when a
                                // SnackbarController is queued but not yet attached to
                                // the Overlay, its late AnimationController throws
                                // LateInitializationError.
                                Navigator.of(ctx).pop();
                                widget.onSelected(wh);
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
