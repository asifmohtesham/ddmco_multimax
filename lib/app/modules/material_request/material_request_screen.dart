import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/modules/global_widgets/role_guard.dart';
import 'package:multimax/app/data/models/material_request_model.dart';

class MaterialRequestScreen extends GetView<MaterialRequestController> {
  const MaterialRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      drawer: const AppNavDrawer(),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchMaterialRequests(clear: true),
        child: CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Material Requests'),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  onChanged: controller.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search ID...',
                    prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
            Obx(() {
              if (controller.isLoading.value && controller.materialRequests.isEmpty) {
                return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
              }
              if (controller.materialRequests.isEmpty) {
                return const SliverFillRemaining(child: Center(child: Text('No Material Requests')));
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    if (index >= controller.materialRequests.length) return null;
                    final req = controller.materialRequests[index];

                    return Obx(() {
                      final isExpanded = controller.expandedRequestId.value == req.name;

                      return GenericDocumentCard(
                        title: req.materialRequestType,
                        subtitle: req.name,
                        status: req.status,
                        stats: [
                          GenericDocumentCard.buildIconStat(context, Icons.calendar_today, req.transactionDate),
                          if (req.scheduleDate.isNotEmpty)
                            GenericDocumentCard.buildIconStat(context, Icons.event, 'Due: ${req.scheduleDate}'),
                        ],
                        isExpanded: isExpanded,
                        onTap: () => controller.toggleExpand(req.name),
                        expandedContent: isExpanded ? _buildExpandedActions(context, req) : null,
                      );
                    });
                  },
                  childCount: controller.materialRequests.length,
                ),
              );
            }),
          ],
        ),
      ),
      floatingActionButton: Obx(() => RoleGuard(
        roles: controller.writeRoles.toList(),
        child: FloatingActionButton.extended(
          onPressed: () {
            Get.toNamed(AppRoutes.MATERIAL_REQUEST_FORM, arguments: {'name': '', 'mode': 'new'});
          },
          icon: const Icon(Icons.add),
          label: const Text('Create'),
        ),
      )),
    );
  }

  Widget _buildExpandedActions(BuildContext context, MaterialRequest req) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // View Button (Available for Submitted documents or if user lacks write access)
          if (req.docstatus != 0)
            FilledButton.tonalIcon(
              onPressed: () => Get.toNamed(AppRoutes.MATERIAL_REQUEST_FORM, arguments: {'name': req.name, 'mode': 'view'}),
              icon: const Icon(Icons.visibility),
              label: const Text('View Details'),
            ),

          // Draft Actions (Edit/Delete)
          if (req.docstatus == 0) ...[
            // Delete Button
            RoleGuard(
              roles: controller.writeRoles.toList(),
              child: IconButton.filled(
                onPressed: () => controller.deleteMaterialRequest(req.name),
                icon: const Icon(Icons.delete_outline),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red,
                ),
                tooltip: 'Delete',
              ),
            ),

            const SizedBox(width: 8),

            // Edit Button
            RoleGuard(
              roles: controller.writeRoles.toList(),
              fallback: FilledButton.tonalIcon(
                onPressed: () => Get.toNamed(AppRoutes.MATERIAL_REQUEST_FORM, arguments: {'name': req.name, 'mode': 'view'}),
                icon: const Icon(Icons.visibility),
                label: const Text('View'),
              ),
              child: FilledButton.tonalIcon(
                onPressed: () => Get.toNamed(AppRoutes.MATERIAL_REQUEST_FORM, arguments: {'name': req.name, 'mode': 'edit'}),
                icon: const Icon(Icons.edit),
                label: const Text('Edit'),
              ),
            ),
          ]
        ],
      ),
    );
  }
}