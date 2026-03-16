import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/work_order_model.dart';
import 'package:multimax/app/data/providers/work_order_provider.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class WorkOrderFormController extends GetxController {
  final WorkOrderProvider _provider = Get.find<WorkOrderProvider>();
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // ── Route args ────────────────────────────────────────────────────────────
  late String name;
  late String mode; // 'new' | 'view'

  // ── Rx state ─────────────────────────────────────────────────────────────
  final isLoading = true.obs;
  final isSaving = false.obs;
  final isDirty = false.obs;
  final isFetchingBom = false.obs;
  final isFetchingWarehouses = false.obs;
  final isFetchingItems = false.obs;

  final workOrder = Rx<WorkOrder?>(null);

  // ── Dropdown / picker data ────────────────────────────────────────────────
  final warehouses = <String>[].obs;
  final bomOptions = <String>[].obs;
  final itemOptions = <String>[].obs;

  // ── Form controllers ──────────────────────────────────────────────────────
  final itemController = TextEditingController();
  final bomController = TextEditingController();
  final qtyController = TextEditingController();
  final plannedStartController = TextEditingController();
  final expectedEndController = TextEditingController();
  final wipWarehouseController = TextEditingController();
  final fgWarehouseController = TextEditingController();
  final descriptionController = TextEditingController();

  // ── Observables for reactive UI ───────────────────────────────────────────
  final selectedItem = RxnString();
  final selectedBom = RxnString();
  final selectedItemName = RxnString();
  final isItemValid = false.obs;
  final isBomValid = false.obs;
  final isQtyValid = false.obs;

  @override
  void onInit() {
    super.onInit();
    name = Get.arguments?['name'] ?? '';
    mode = Get.arguments?['mode'] ?? 'view';

    qtyController.addListener(_validateForm);
    itemController.addListener(_validateForm);

    fetchWarehouses();

    if (mode == 'new') {
      _initNew();
    } else {
      _fetchDocument();
    }
  }

  @override
  void onClose() {
    itemController.dispose();
    bomController.dispose();
    qtyController.dispose();
    plannedStartController.dispose();
    expectedEndController.dispose();
    wipWarehouseController.dispose();
    fgWarehouseController.dispose();
    descriptionController.dispose();
    super.onClose();
  }

  bool get canEdit => workOrder.value?.docstatus == 0 || mode == 'new';
  bool get canSave =>
      isDirty.value && isItemValid.value && isBomValid.value && isQtyValid.value;

  // ── Init ──────────────────────────────────────────────────────────────────

  void _initNew() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    plannedStartController.text = today;
    qtyController.text = '1';
    isLoading.value = false;
    isDirty.value = false;
    workOrder.value = WorkOrder(
      name: 'New Work Order',
      productionItem: '',
      itemName: '',
      bomNo: '',
      qty: 1,
      producedQty: 0,
      status: 'Draft',
      plannedStartDate: today,
      docstatus: 0,
    );
  }

  Future<void> _fetchDocument() async {
    isLoading.value = true;
    try {
      final res = await _provider.getWorkOrder(name);
      if (res.statusCode == 200 && res.data['data'] != null) {
        final wo = WorkOrder.fromJson(res.data['data']);
        workOrder.value = wo;
        _populateControllers(wo);
        isDirty.value = false;
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load Work Order');
    } finally {
      isLoading.value = false;
    }
  }

  void _populateControllers(WorkOrder wo) {
    itemController.text = wo.productionItem;
    selectedItem.value = wo.productionItem;
    selectedItemName.value = wo.itemName;
    bomController.text = wo.bomNo;
    selectedBom.value = wo.bomNo;
    qtyController.text =
        wo.qty % 1 == 0 ? wo.qty.toInt().toString() : wo.qty.toString();
    plannedStartController.text = wo.plannedStartDate;
    expectedEndController.text = wo.expectedEndDate ?? '';
    wipWarehouseController.text = wo.wip_warehouse ?? '';
    fgWarehouseController.text = wo.fg_warehouse ?? '';
    descriptionController.text = wo.description ?? '';
    _validateForm();
  }

  /// Public so the form screen's onChanged callbacks can call it directly.
  void markDirty() {
    if (!isLoading.value) isDirty.value = true;
  }

  void _validateForm() {
    isItemValid.value = (selectedItem.value ?? '').isNotEmpty;
    isBomValid.value = (selectedBom.value ?? '').isNotEmpty;
    final qty = double.tryParse(qtyController.text) ?? 0;
    isQtyValid.value = qty > 0;
  }

  // ── Fetch warehouses ──────────────────────────────────────────────────────

  Future<void> fetchWarehouses() async {
    isFetchingWarehouses.value = true;
    try {
      final res = await _apiProvider.getDocumentList(
        'Warehouse',
        filters: {'is_group': 0},
        limit: 200,
      );
      if (res.statusCode == 200 && res.data['data'] != null) {
        warehouses.value = (res.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (_) {} finally {
      isFetchingWarehouses.value = false;
    }
  }

  // ── Item search ───────────────────────────────────────────────────────────

  Future<void> searchItems(String query) async {
    if (query.length < 2) {
      itemOptions.clear();
      return;
    }
    isFetchingItems.value = true;
    try {
      final res = await _apiProvider.getDocumentList(
        'Item',
        filters: {
          'name': ['like', '%$query%'],
          'is_sales_item': 0,
        },
        fields: ['name', 'item_name'],
        limit: 20,
      );
      if (res.statusCode == 200 && res.data['data'] != null) {
        itemOptions.value = (res.data['data'] as List)
            .map((e) => e['name'] as String)
            .toList();
      }
    } catch (_) {} finally {
      isFetchingItems.value = false;
    }
  }

  void onItemSelected(String itemCode) async {
    selectedItem.value = itemCode;
    itemController.text = itemCode;
    itemOptions.clear();

    try {
      final res = await _apiProvider.getDocument('Item', itemCode);
      if (res.statusCode == 200 && res.data['data'] != null) {
        selectedItemName.value = res.data['data']['item_name'] ?? itemCode;
      }
    } catch (_) {}

    bomController.clear();
    selectedBom.value = null;
    isBomValid.value = false;
    bomOptions.clear();
    markDirty();
    _validateForm();
    await _autoLoadBom(itemCode);
  }

  Future<void> _autoLoadBom(String itemCode) async {
    isFetchingBom.value = true;
    try {
      final res = await _provider.searchBoms(itemCode);
      if (res.statusCode == 200 && res.data['data'] != null) {
        final list = res.data['data'] as List;
        if (list.isNotEmpty) {
          await _applyBom(list.first['name'] as String);
          return;
        }
      }
      final res2 = await _provider.getBomsForItem(itemCode);
      if (res2.statusCode == 200 && res2.data['data'] != null) {
        final list2 = res2.data['data'] as List;
        if (list2.isNotEmpty) {
          bomOptions.value = list2.map((e) => e['name'] as String).toList();
          if (list2.length == 1) {
            await _applyBom(list2.first['name'] as String);
          }
        }
      }
    } catch (_) {} finally {
      isFetchingBom.value = false;
    }
  }

  Future<void> _applyBom(String bomName) async {
    try {
      final res = await _provider.getBom(bomName);
      if (res.statusCode == 200 && res.data['data'] != null) {
        final bom = res.data['data'];
        bomController.text = bomName;
        selectedBom.value = bomName;
        if (wipWarehouseController.text.isEmpty) {
          wipWarehouseController.text = bom['wip_warehouse'] ?? '';
        }
        if (fgWarehouseController.text.isEmpty) {
          fgWarehouseController.text = bom['fg_warehouse'] ?? '';
        }
        markDirty();
        _validateForm();
      }
    } catch (_) {}
  }

  void onBomSelected(String bomName) async {
    bomOptions.clear();
    await _applyBom(bomName);
  }

  // ── Date pickers ──────────────────────────────────────────────────────────

  Future<void> pickDate(TextEditingController ctrl) async {
    if (!canEdit) return;
    final now = DateTime.now();
    DateTime initial = now;
    try {
      if (ctrl.text.isNotEmpty) {
        initial = DateFormat('yyyy-MM-dd').parse(ctrl.text);
      }
    } catch (_) {}
    final picked = await showDatePicker(
      context: Get.context!,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
      markDirty();
    }
  }

  // ── Warehouse picker (bottom sheet) ───────────────────────────────────────

  void showWarehousePicker(TextEditingController ctrl) {
    if (!canEdit) return;
    final search = TextEditingController();
    final filtered = warehouses.toList().obs;
    Get.bottomSheet(
      Container(
        height: Get.height * 0.65,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Select Warehouse',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: search,
              decoration: const InputDecoration(
                hintText: 'Search warehouse…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) {
                filtered.value = warehouses
                    .where((w) => w.toLowerCase().contains(v.toLowerCase()))
                    .toList();
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Obx(() {
                if (isFetchingWarehouses.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (filtered.isEmpty) {
                  return const Center(child: Text('No warehouses found'));
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => ListTile(
                    title: Text(filtered[i]),
                    onTap: () {
                      ctrl.text = filtered[i];
                      markDirty();
                      Get.back();
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  // ── BOM picker (bottom sheet) ─────────────────────────────────────────────

  void showBomPicker() {
    if (!canEdit) return;
    if (bomOptions.isEmpty) {
      GlobalSnackbar.info(message: 'Select an item first to load BOMs');
      return;
    }
    Get.bottomSheet(
      Container(
        constraints: BoxConstraints(maxHeight: Get.height * 0.55),
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Select BOM',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: bomOptions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: Text(bomOptions[i]),
                  onTap: () {
                    Get.back();
                    onBomSelected(bomOptions[i]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Adjust qty ────────────────────────────────────────────────────────────

  void adjustQty(int delta) {
    if (!canEdit) return;
    final current = double.tryParse(qtyController.text) ?? 0;
    final newVal = (current + delta).clamp(1, double.infinity);
    qtyController.text =
        newVal % 1 == 0 ? newVal.toInt().toString() : newVal.toString();
    markDirty();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> save() async {
    if (isSaving.value || !canSave) return;
    isSaving.value = true;

    final qty = double.tryParse(qtyController.text) ?? 0;
    final data = <String, dynamic>{
      'production_item': selectedItem.value,
      'bom_no': selectedBom.value,
      'qty': qty,
      'planned_start_date': plannedStartController.text,
      if (expectedEndController.text.isNotEmpty)
        'expected_end_date': expectedEndController.text,
      if (wipWarehouseController.text.isNotEmpty)
        'wip_warehouse': wipWarehouseController.text,
      if (fgWarehouseController.text.isNotEmpty)
        'fg_warehouse': fgWarehouseController.text,
      if (descriptionController.text.isNotEmpty)
        'description': descriptionController.text,
    };

    try {
      if (mode == 'new') {
        final res = await _provider.createWorkOrder(data);
        if (res.statusCode == 200 && res.data['data'] != null) {
          name = res.data['data']['name'];
          mode = 'view';
          await _fetchDocument();
          GlobalSnackbar.success(message: 'Work Order $name created');
          isDirty.value = false;
        } else {
          GlobalSnackbar.error(message: 'Failed to create Work Order');
        }
      } else {
        data['modified'] = workOrder.value?.modified;
        final res = await _provider.updateWorkOrder(name, data);
        if (res.statusCode == 200) {
          await _fetchDocument();
          GlobalSnackbar.success(message: 'Work Order updated');
          isDirty.value = false;
        } else {
          GlobalSnackbar.error(message: 'Failed to update Work Order');
        }
      }
    } on DioException catch (e) {
      String msg = 'Save failed';
      if (e.response?.data is Map) {
        final ex = e.response!.data['exception']?.toString() ?? '';
        if (ex.isNotEmpty) msg = ex.split(':').last.trim();
      }
      GlobalSnackbar.error(message: msg);
    } catch (e) {
      GlobalSnackbar.error(message: 'Error: $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ── Discard guard ─────────────────────────────────────────────────────────

  Future<void> confirmDiscard() async {
    GlobalDialog.showUnsavedChanges(
      onDiscard: () {
        isDirty.value = false;
        Get.back();
      },
    );
  }
}
