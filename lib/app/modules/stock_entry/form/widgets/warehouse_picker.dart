import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/utils/navigator_utils.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

/// Bottom-sheet warehouse selector.
/// Step 8 — extracted from StockEntryFormScreen._showWarehousePicker().
class WarehousePicker {
  WarehousePicker._();

  static void show(
    BuildContext context,
    StockEntryFormController controller, {
    required bool isSource,
  }) {
    if (controller.warehouses.isEmpty &&
        !controller.isFetchingWarehouses.value) {
      controller.fetchWarehouses();
    }

    final searchController = TextEditingController();
    final filteredWarehouses = RxList<String>(controller.warehouses);

    Get.bottomSheet(
      // Builder provides a context that is *inside* the sheet's route so
      // Navigator.of(ctx).pop() closes only this sheet and never touches
      // the GetX snackbar queue (unlike Get.back() which calls
      // closeCurrentSnackbar() unconditionally).
      Builder(
        builder: (ctx) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Text(
                isSource
                    ? 'Select Source Warehouse'
                    : 'Select Target Warehouse',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  labelText: 'Search Warehouses',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  filteredWarehouses.assignAll(
                    val.isEmpty
                        ? controller.warehouses
                        : controller.warehouses.where((w) =>
                            w.toLowerCase().contains(val.toLowerCase())),
                  );
                },
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Obx(() {
                  if (controller.isFetchingWarehouses.value) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  if (filteredWarehouses.isEmpty) {
                    return const Center(
                        child: Text('No warehouses found'));
                  }
                  return ListView.separated(
                    itemCount: filteredWarehouses.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final wh = filteredWarehouses[i];
                      final isSelected = isSource
                          ? controller.selectedFromWarehouse.value == wh
                          : controller.selectedToWarehouse.value == wh;
                      return ListTile(
                        title: Text(wh),
                        trailing: isSelected
                            ? Icon(Icons.check_circle,
                                color: Theme.of(context).primaryColor)
                            : null,
                        onTap: () {
                          if (isSource) {
                            controller.selectedFromWarehouse.value = wh;
                          } else {
                            controller.selectedToWarehouse.value = wh;
                          }
                          NavigatorUtils.popSheet(ctx);
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
      isScrollControlled: true,
    );
  }
}
