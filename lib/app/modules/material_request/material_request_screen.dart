import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';
import 'package:multimax/app/data/models/material_request_model.dart';
import 'package:multimax/app/modules/global_widgets/generic_list_page.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/role_guard.dart';
import 'package:multimax/theme/frappe_theme.dart';

class MaterialRequestScreen extends GetView<MaterialRequestController> {
  const MaterialRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Scroll controller for pagination
    final scrollController = ScrollController();
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent * 0.9 &&
          controller.hasMore.value &&
          !controller.isFetchingMore.value) {
        controller.fetchMaterialRequests(isLoadMore: true);
      }
    });

    return GenericListPage(
      title: 'Material Requests',
      isLoading: controller.isLoading,
      data: controller.filteredList,
      onRefresh: () async => controller.fetchMaterialRequests(clear: true),
      scrollController: scrollController,

      // Search Config
      onSearch: controller.onSearchChanged,
      searchHint: 'Search ID...',
      searchDoctype: 'Material Request',

      // Create Button
      fab: Obx(() => RoleGuard(
        roles: controller.writeRoles.toList(),
        child: FloatingActionButton.extended(
          backgroundColor: FrappeTheme.primary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('Create', style: TextStyle(color: Colors.white)),
          onPressed: () => controller.openForm('', mode: 'new'),
        ),
      )),

      itemBuilder: (context, index) {
        // Pagination Loader
        if (index == controller.filteredList.length) {
          return controller.hasMore.value
              ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              : const SizedBox.shrink();
        }

        final req = controller.filteredList[index];
        return _buildRequestCard(context, req);
      },
    );
  }

  Widget _buildRequestCard(BuildContext context, MaterialRequest req) {
    return Obx(() {
      final isExpanded = controller.expandedRequestId.value == req.name;

      return GenericDocumentCard(
        title: req.materialRequestType,
        subtitle: req.name,
        status: req.status,

        // Custom Leading Icon
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: FrappeTheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.assignment_outlined, color: FrappeTheme.primary, size: 22),
        ),

        stats: [
          GenericDocumentCard.buildIconStat(context, Icons.calendar_today, req.transactionDate),
          if (req.scheduleDate.isNotEmpty)
            GenericDocumentCard.buildIconStat(context, Icons.event, 'Due: ${req.scheduleDate}'),
        ],

        isExpanded: isExpanded,
        onTap: () => controller.toggleExpand(req.name),
        expandedContent: isExpanded ? _buildActions(context, req) : null,
      );
    });
  }

  Widget _buildActions(BuildContext context, MaterialRequest req) {
    final bool isDraft = req.docstatus == 0;

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // View Button (Always visible)
          if (!isDraft)
            ElevatedButton.icon(
              onPressed: () => controller.openForm(req.name, mode: 'view'),
              icon: const Icon(Icons.visibility, size: 16),
              label: const Text('View Details'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FrappeTheme.surface,
                foregroundColor: FrappeTheme.textBody,
                elevation: 0,
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),

          // Draft Actions (Edit/Delete)
          if (isDraft) ...[
            RoleGuard(
              roles: controller.writeRoles.toList(),
              child: IconButton(
                onPressed: () => controller.deleteMaterialRequest(req.name),
                icon: const Icon(Icons.delete_outline),
                color: Colors.red,
                tooltip: 'Delete',
              ),
            ),
            const SizedBox(width: 8),
            RoleGuard(
              roles: controller.writeRoles.toList(),
              fallback: ElevatedButton.icon(
                onPressed: () => controller.openForm(req.name, mode: 'view'),
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text('View'),
              ),
              child: ElevatedButton.icon(
                onPressed: () => controller.openForm(req.name, mode: 'edit'),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FrappeTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
              ),
            ),
          ]
        ],
      ),
    );
  }
}