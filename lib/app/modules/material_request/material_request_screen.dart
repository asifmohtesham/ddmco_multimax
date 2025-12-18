import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/material_request/material_request_controller.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/generic_document_card.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

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
                    return GenericDocumentCard(
                      title: req.materialRequestType,
                      subtitle: req.name,
                      status: req.status,
                      stats: [
                        GenericDocumentCard.buildIconStat(context, Icons.calendar_today, req.transactionDate),
                        if (req.scheduleDate.isNotEmpty)
                          GenericDocumentCard.buildIconStat(context, Icons.event, 'Due: ${req.scheduleDate}'),
                      ],
                      onTap: () {
                        // Navigation to Detail/Form would go here
                        // Get.toNamed(AppRoutes.MATERIAL_REQUEST_FORM, arguments: {'name': req.name});
                      },
                      isExpanded: false,
                    );
                  },
                  childCount: controller.materialRequests.length,
                ),
              );
            }),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Get.toNamed(AppRoutes.MATERIAL_REQUEST_FORM, arguments: {'name': '', 'mode': 'new'});
        },
        icon: const Icon(Icons.add),
        label: const Text('Create'),
      ),
    );
  }
}