import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/stock_entry/form/stock_entry_form_controller.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/details_tab.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/items_tab/standard_items_view.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/items_tab/mr_items_view.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/items_tab/pos_upload_items_view.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/items_tab/empty_scan_state.dart';
import 'package:multimax/app/modules/stock_entry/form/widgets/items_tab/bottom_scan_bar.dart';

/// Root screen for the Stock Entry form.
/// All substantive UI lives in focused sub-widgets — this class is a pure
/// orchestrator (~70 lines) after the Steps 1–9 refactor.
class StockEntryFormScreen extends GetView<StockEntryFormController> {
  const StockEntryFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final entry = controller.stockEntry.value;
      final bool isEditable = entry?.docstatus == 0;

      final VoidCallback? onSave =
          isEditable ? controller.saveStockEntry : null;
      final VoidCallback? onReload =
          controller.mode != 'new' ? controller.reloadDocument : null;

      final String title = entry == null
          ? 'Loading...'
          : (entry.name?.isNotEmpty == true
              ? entry.name!
              : 'New ${controller.selectedStockEntryType.value}');

      return PopScope(
        canPop: !controller.isDirty.value,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await controller.confirmDiscard();
        },
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: MainAppBar(
              title: title,
              status: entry?.status,
              isDirty: controller.isDirty.value,
              isSaving: controller.isSaving.value,
              onSave: onSave,
              onReload: onReload,
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Details'),
                  Tab(text: 'Items & Scan'),
                ],
              ),
            ),
            body: Builder(builder: (context) {
              if (controller.isLoading.value) {
                return const Center(child: CircularProgressIndicator());
              }
              if (entry == null) {
                return const Center(
                    child: Text('Stock entry not found.'));
              }
              return TabBarView(
                children: [
                  DetailsTab(
                      controller: controller, entry: entry),
                  _ItemsTab(controller: controller, entry: entry),
                ],
              );
            }),
          ),
        ),
      );
    });
  }
}

/// Items & Scan tab — selects the correct items view based on [entrySource]
/// and pins [BottomScanBar] over the list.
class _ItemsTab extends StatelessWidget {
  final StockEntryFormController controller;

  const _ItemsTab(
      {required this.controller, required StockEntry entry})
      : _entry = entry;

  final StockEntry _entry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Builder(builder: (_) {
                if (_entry.items.isEmpty &&
                    controller.entrySource !=
                        StockEntrySource.posUpload &&
                    controller.entrySource !=
                        StockEntrySource.materialRequest) {
                  return const EmptyScanState();
                }
                switch (controller.entrySource) {
                  case StockEntrySource.posUpload:
                    return PosUploadItemsView(
                        controller: controller, entry: _entry);
                  case StockEntrySource.materialRequest:
                    return MrItemsView(
                        controller: controller, entry: _entry);
                  case StockEntrySource.manual:
                  default:
                    return StandardItemsView(
                        controller: controller, entry: _entry);
                }
              }),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: BottomScanBar(controller: controller),
        ),
      ],
    );
  }
}
