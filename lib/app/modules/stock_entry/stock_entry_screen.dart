import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/widgets/frappe_filter_bottom_sheet.dart';
import 'package:multimax/controllers/frappe_filter_sheet_controller.dart';
import 'package:multimax/theme/frappe_theme.dart';

class StockEntryScreen extends GetView<StockEntryController> {
  const StockEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Correct Pagination Logic
    final scrollController = ScrollController();
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent * 0.9 &&
          controller.hasMore.value &&
          !controller.isFetchingMore.value) {
        controller.loadMore();
      }
    });

    return GenericListPage(
      title: 'Stock Entry',
      isLoading: controller.isLoading,
      data: controller.list,
      onRefresh: () async => controller.refreshList(),
      scrollController: scrollController,

      onSearch: controller.onSearchChanged,
      searchHint: 'Search ID or Type...',
      searchDoctype: 'Stock Entry',

      fab: FloatingActionButton(
        backgroundColor: FrappeTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => Get.toNamed(
            AppRoutes.STOCK_ENTRY_FORM,
            arguments: {'mode': 'new'}
        ),
      ),

      actions: [
        Obx(() => IconButton(
          icon: Badge(
            isLabelVisible: controller.activeFilters.isNotEmpty,
            backgroundColor: FrappeTheme.primary,
            label: Text('${controller.activeFilters.length}'),
            child: Icon(
                Icons.filter_list_rounded,
                color: controller.activeFilters.isNotEmpty ? FrappeTheme.primary : FrappeTheme.textBody
            ),
          ),
          onPressed: () {
            final sheetCtrl = Get.put(FrappeFilterSheetController());
            sheetCtrl.initialize(controller);
            Get.bottomSheet(
              const FrappeFilterBottomSheet(),
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
            ).then((_) => Get.delete<FrappeFilterSheetController>());
          },
        )),
      ],

      itemBuilder: (context, index) {
        if (index >= controller.list.length) {
          return controller.hasMore.value
              ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              : const SizedBox.shrink();
        }

        final doc = controller.list[index];
        final status = controller.getStatus(doc);

        return GenericDocumentCard(
          title: doc['name'] ?? '',
          subtitle: doc['stock_entry_type'] ?? doc['purpose'] ?? '',
          status: status,
          // Removed invalid 'statusColor' parameter
          isExpanded: false,
          onTap: () => Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {'name': doc['name']}),
          stats: [
            GenericDocumentCard.buildIconStat(context, Icons.calendar_today, doc['posting_date'] ?? ''),
            if (doc['from_warehouse'] != null)
              GenericDocumentCard.buildIconStat(context, Icons.output, doc['from_warehouse']),
            if (doc['to_warehouse'] != null)
              GenericDocumentCard.buildIconStat(context, Icons.input, doc['to_warehouse']),
          ],
        );
      },
    );
  }
}