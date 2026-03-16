import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';

// ---------------------------------------------------------------------------
// BatchFilterBottomSheet
// ---------------------------------------------------------------------------
// Each of the four key fields — Item Code, Batch No, Purchase Order, Supplier
// Name — is presented as an InkWell tile that opens a searchable
// DraggableScrollableSheet picker.  The picker fires a live API search on the
// controller’s provider so users always see up-to-date values without having
// to pre-load a potentially large list.
// ---------------------------------------------------------------------------

class BatchFilterBottomSheet extends StatefulWidget {
  const BatchFilterBottomSheet({super.key});

  @override
  State<BatchFilterBottomSheet> createState() =>
      _BatchFilterBottomSheetState();
}

class _BatchFilterBottomSheetState extends State<BatchFilterBottomSheet> {
  final BatchController _ctrl = Get.find();

  // Local copies — committed only on “Apply”
  final _itemCode = ''.obs;
  final _batchNo = ''.obs;
  final _purchaseOrder = ''.obs;
  final _supplierName = ''.obs;
  final _showDisabled = false.obs;
  late String _sortField;
  late String _sortOrder;

  @override
  void initState() {
    super.initState();
    final af = _ctrl.activeFilters;
    _itemCode.value = af['item'] as String? ?? '';
    _batchNo.value = (af['name'] is List
        ? (af['name'] as List)[1].toString().replaceAll('%', '')
        : af['name'] as String? ?? '');
    _purchaseOrder.value = af['custom_purchase_order'] as String? ?? '';
    _supplierName.value = af['custom_supplier_name'] as String? ?? '';
    _showDisabled.value = (af['disabled'] == 1);
    _sortField = _ctrl.sortField.value;
    _sortOrder = _ctrl.sortOrder.value;
  }

  // ── Searchable picker sheet ───────────────────────────────────────────────

  void _showSearchPicker({
    required BuildContext context,
    required String title,
    required String hintText,
    required Future<List<_PickerItem>> Function(String query) searcher,
    required void Function(String value, String label) onSelected,
  }) {
    final searchController = TextEditingController();
    final results = <_PickerItem>[].obs;
    final isLoading = false.obs;

    () async {
      isLoading.value = true;
      results.value = await searcher('');
      isLoading.value = false;
    }();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx2, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: hintText,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (val) async {
                  isLoading.value = true;
                  results.value = await searcher(val);
                  isLoading.value = false;
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Obx(() {
                  if (isLoading.value) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (results.isEmpty) {
                    return const Center(child: Text('No results'));
                  }
                  return ListView.separated(
                    controller: scrollController,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final item = results[i];
                      return ListTile(
                        title: Text(item.label),
                        subtitle: item.subtitle != null
                            ? Text(item.subtitle!,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey))
                            : null,
                        onTap: () {
                          onSelected(item.value, item.label);
                          Navigator.of(ctx).pop();
                        },
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Searcher helpers ──────────────────────────────────────────────────────────

  Future<List<_PickerItem>> _searchItems(String q) async {
    try {
      final res = await _ctrl.batchProvider.searchItems(q);
      if (res.statusCode == 200 && res.data['data'] != null) {
        return (res.data['data'] as List).map((e) {
          final code = e['item_code'] as String? ?? '';
          final name = e['item_name'] as String? ?? '';
          return _PickerItem(
              value: code,
              label: code,
              subtitle: name != code ? name : null);
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<_PickerItem>> _searchBatches(String q) async {
    try {
      final res = await _ctrl.batchProvider.searchBatchNames(q);
      if (res.statusCode == 200 && res.data['data'] != null) {
        return (res.data['data'] as List).map((e) {
          final name = e['name'] as String? ?? '';
          final item = e['item'] as String? ?? '';
          return _PickerItem(
              value: name,
              label: name,
              subtitle: item.isNotEmpty ? item : null);
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<_PickerItem>> _searchPOs(String q) async {
    try {
      final res = await _ctrl.batchProvider.searchPurchaseOrders(q);
      if (res.statusCode == 200 && res.data['data'] != null) {
        return (res.data['data'] as List).map((e) {
          final name = e['name'] as String? ?? '';
          final supplier = e['supplier'] as String? ?? '';
          return _PickerItem(
              value: name,
              label: name,
              subtitle: supplier.isNotEmpty ? supplier : null);
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<_PickerItem>> _searchSuppliers(String q) async {
    try {
      final res = await _ctrl.batchProvider.searchSuppliers(q);
      if (res.statusCode == 200 && res.data['data'] != null) {
        return (res.data['data'] as List).map((e) {
          final name = e['name'] as String? ?? '';
          final supplierName = e['supplier_name'] as String? ?? '';
          return _PickerItem(
              value: name,
              label: supplierName.isNotEmpty ? supplierName : name,
              subtitle:
                  supplierName != name && name.isNotEmpty ? name : null);
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Apply / Clear ────────────────────────────────────────────────────────────

  void _apply() {
    final filters = <String, dynamic>{};

    if (_itemCode.value.isNotEmpty) filters['item'] = _itemCode.value;
    if (_batchNo.value.isNotEmpty) {
      filters['name'] = ['like', '%${_batchNo.value}%'];
    }
    if (_purchaseOrder.value.isNotEmpty) {
      filters['custom_purchase_order'] = _purchaseOrder.value;
    }
    if (_supplierName.value.isNotEmpty) {
      filters['custom_supplier_name'] = _supplierName.value;
    }
    if (_showDisabled.value) {
      filters['disabled'] = ['in', [0, 1]];
    }

    _ctrl.sortField.value = _sortField;
    _ctrl.sortOrder.value = _sortOrder;
    _ctrl.applyFilters(filters);

    // Use Navigator.pop instead of Get.back().
    // Get.back() unconditionally calls Get.closeCurrentSnackbar() before
    // popping; when no snackbar is queued the late SnackbarController._controller
    // field has not been initialised → LateInitializationError.
    Navigator.of(context).pop();
  }

  void _clear() {
    _itemCode.value = '';
    _batchNo.value = '';
    _purchaseOrder.value = '';
    _supplierName.value = '';
    _showDisabled.value = false;
    _sortField = 'modified';
    _sortOrder = 'desc';
    _ctrl.clearFilters();
    Navigator.of(context).pop(); // same reason as _apply
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  int get _localFilterCount =>
      [_itemCode, _batchNo, _purchaseOrder, _supplierName]
          .where((rx) => rx.value.isNotEmpty)
          .length +
      (_showDisabled.value ? 1 : 0);

  Widget _pickerTile({
    required BuildContext context,
    required String label,
    required RxString value,
    required String hint,
    required Future<List<_PickerItem>> Function(String) searcher,
    required IconData icon,
  }) {
    return Obx(() => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showSearchPicker(
            context: context,
            title: 'Select $label',
            hintText: 'Search $label…',
            searcher: searcher,
            onSelected: (v, _) => value.value = v,
          ),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              prefixIcon: Icon(icon),
              suffixIcon: value.value.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => value.value = '',
                    )
                  : const Icon(Icons.arrow_drop_down),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            child: Text(
              value.value.isNotEmpty ? value.value : hint,
              style: TextStyle(
                color: value.value.isNotEmpty
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                overflow: TextOverflow.ellipsis,
              ),
              maxLines: 1,
            ),
          ),
        ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
          title: 'Filter Batches',
          activeFilterCount: _localFilterCount,
          sortOptions: const [
            SortOption('Modified', 'modified'),
            SortOption('Batch No', 'name'),
            SortOption('Item Code', 'item'),
            SortOption('Expiry Date', 'expiry_date'),
          ],
          currentSortField: _sortField,
          currentSortOrder: _sortOrder,
          onSortChanged: (field, order) {
            setState(() {
              _sortField = field;
              _sortOrder = order;
            });
          },
          onApply: _apply,
          onClear: _clear,
          filterWidgets: [
            const SizedBox(height: 16),
            _pickerTile(
              context: context,
              label: 'Item Code',
              value: _itemCode,
              hint: 'All Items',
              icon: Icons.inventory_2_outlined,
              searcher: _searchItems,
            ),
            const SizedBox(height: 12),
            _pickerTile(
              context: context,
              label: 'Batch No',
              value: _batchNo,
              hint: 'All Batches',
              icon: Icons.qr_code_outlined,
              searcher: _searchBatches,
            ),
            const SizedBox(height: 12),
            _pickerTile(
              context: context,
              label: 'Purchase Order',
              value: _purchaseOrder,
              hint: 'All POs',
              icon: Icons.receipt_long_outlined,
              searcher: _searchPOs,
            ),
            const SizedBox(height: 12),
            _pickerTile(
              context: context,
              label: 'Supplier Name',
              value: _supplierName,
              hint: 'All Suppliers',
              icon: Icons.local_shipping_outlined,
              searcher: _searchSuppliers,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Include Disabled Batches'),
              subtitle:
                  const Text('By default only active batches are shown'),
              value: _showDisabled.value,
              onChanged: (v) => _showDisabled.value = v,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ));
  }
}

// ── Internal data model for picker results ────────────────────────────────────────

class _PickerItem {
  final String value;
  final String label;
  final String? subtitle;
  const _PickerItem(
      {required this.value, required this.label, this.subtitle});
}
