// app/modules/batch/batch_screen.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';

class BatchScreen extends GetView<BatchController> {
  const BatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent * 0.9 &&
          controller.hasMore.value &&
          !controller.isFetchingMore.value) {
        controller.fetchBatches(isLoadMore: true);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Batches')),
      drawer: const AppNavDrawer(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              onChanged: controller.onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search Batch ID...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
          ),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value && controller.batches.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              if (controller.batches.isEmpty) {
                return const Center(child: Text('No batches found.'));
              }
              return RefreshIndicator(
                onRefresh: () => controller.fetchBatches(clear: true),
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: controller.batches.length + (controller.hasMore.value ? 1 : 0),
                  separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, index) {
                    if (index >= controller.batches.length) {
                      return const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
                    }
                    final batch = controller.batches[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Text(batch.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey),
                              const SizedBox(width: 4),
                              Expanded(child: Text(batch.item, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          if (batch.expiryDate != null) ...[
                            const SizedBox(height: 4),
                            Text('Expires: ${batch.expiryDate}', style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                          ]
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                      onTap: () => controller.openBatchForm(batch.name),
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => controller.openBatchForm(null),
        child: const Icon(Icons.add),
      ),
    );
  }
}