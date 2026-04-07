import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';

/// Bottom-sheet Stock Entry type selector.
/// Step 8 — extracted from StockEntryFormScreen._showStockEntryTypePicker().
class EntryTypePicker {
  EntryTypePicker._();

  static void show(
    BuildContext context,
    StockEntryFormController controller,
  ) {
    final searchController = TextEditingController();
    final filteredTypes =
        RxList<String>(controller.stockEntryTypes);

    Get.bottomSheet(
      // Builder provides a context that is *inside* the sheet's route so
      // Navigator.of(ctx).pop() closes only this sheet and never touches
      // the GetX snackbar queue (unlike Get.back() which calls
      // closeCurrentSnackbar() unconditionally — risking LateInitializationError
      // when a snackbar is queued but not yet attached to the Overlay).
      Builder(
        builder: (ctx) => SafeArea(
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                padding: const EdgeInsets.all(16.0),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16.0)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Select Entry Type',
                            style:
                                Theme.of(context).textTheme.titleLarge),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search Types',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16),
                      ),
                      onChanged: (val) {
                        filteredTypes.assignAll(
                          val.isEmpty
                              ? controller.stockEntryTypes
                              : controller.stockEntryTypes.where((t) =>
                                  t.toLowerCase()
                                      .contains(val.toLowerCase())),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Obx(() {
                        if (controller.isFetchingTypes.value) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (filteredTypes.isEmpty) {
                          return const Center(
                              child: Text('No types found'));
                        }
                        return ListView.separated(
                          controller: scrollController,
                          itemCount: filteredTypes.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final type = filteredTypes[index];
                            final isSelected = type ==
                                controller
                                    .selectedStockEntryType.value;
                            return ListTile(
                              title: Text(
                                type,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                controller.getTypeHelperText(type),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: Colors.grey.shade700),
                              ),
                              isThreeLine: true,
                              trailing: isSelected
                                  ? Icon(Icons.check_circle,
                                      color: Theme.of(context)
                                          .primaryColor)
                                  : null,
                              onTap: () {
                                controller
                                    .selectedStockEntryType.value = type;
                                Navigator.of(ctx).pop();
                              },
                            );
                          },
                        );
                      }),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }
}
