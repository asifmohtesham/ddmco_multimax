import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:ddmco_multimax/app/modules/stock_entry/stock_entry_controller.dart';
import 'package:intl/intl.dart';
import 'package:ddmco_multimax/app/data/routes/app_routes.dart';
import 'package:ddmco_multimax/app/modules/global_widgets/status_pill.dart';

class StockEntryScreen extends StatefulWidget {
  const StockEntryScreen({super.key});

  @override
  State<StockEntryScreen> createState() => _StockEntryScreenState();
}

class _StockEntryScreenState extends State<StockEntryScreen> {
  final StockEntryController controller = Get.find();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom && controller.hasMore.value && !controller.isFetchingMore.value) {
      controller.fetchStockEntries(isLoadMore: true);
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  void _showFilterDialog(BuildContext context) {
    final purposeController = TextEditingController(text: controller.activeFilters['purpose']);
    int? selectedDocstatus = controller.activeFilters['docstatus'];

    Get.dialog(
      AlertDialog(
        title: const Text('Filter Stock Entries'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: purposeController,
              decoration: const InputDecoration(labelText: 'Purpose'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: selectedDocstatus,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Draft')),
                DropdownMenuItem(value: 1, child: Text('Submitted')),
                DropdownMenuItem(value: 2, child: Text('Cancelled')),
              ],
              onChanged: (value) => selectedDocstatus = value,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.clearFilters();
              Get.back();
            },
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () {
              final filters = {
                if (purposeController.text.isNotEmpty) 'purpose': purposeController.text,
                if (selectedDocstatus != null) 'docstatus': selectedDocstatus,
              };
              controller.applyFilters(filters);
              Get.back();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Entries'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => _showFilterDialog(context),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.stockEntries.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.stockEntries.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No stock entries found.'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => controller.fetchStockEntries(clear: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => controller.fetchStockEntries(clear: true),
          child: Scrollbar(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: controller.stockEntries.length + (controller.hasMore.value ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= controller.stockEntries.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final entry = controller.stockEntries[index];
                return StockEntryCard(entry: entry);
              },
            ),
          ),
        );
      }),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {'name': '', 'mode': 'new'});
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class StockEntryCard extends StatelessWidget {
  final dynamic entry;
  final StockEntryController controller = Get.find();

  StockEntryCard({super.key, required this.entry});

  String _getRelativeTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => controller.toggleExpand(entry.name),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Purpose + Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      entry.purpose,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: entry.status),
                ],
              ),
              const SizedBox(height: 6),
              
              // Row 2: Name + Time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      entry.name,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _getRelativeTime(entry.creation),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),

              // Expansion Content
              Obx(() {
                final isCurrentlyExpanded = controller.expandedEntryName.value == entry.name;
                return AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: Container(
                    child: !isCurrentlyExpanded
                        ? const SizedBox.shrink()
                        : Obx(() {
                            final detailed = controller.detailedEntry;
                            if (controller.isLoadingDetails.value && detailed?.name != entry.name) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                                );
                            }

                            if (detailed != null && detailed.name == entry.name) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Divider(height: 1),
                                    const SizedBox(height: 8),
                                    Text('Total Amount: \$${detailed.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    Text('Posting Date: ${detailed.postingDate}', style: const TextStyle(color: Colors.grey)),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (detailed.status == 'Draft') ...[
                                          OutlinedButton.icon(
                                            onPressed: () => Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {'name': entry.name, 'mode': 'edit'}),
                                            icon: const Icon(Icons.edit, size: 18),
                                            label: const Text('Edit'),
                                            style: OutlinedButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              side: const BorderSide(color: Colors.blue),
                                            ),
                                          ),
                                        ] else ...[
                                          TextButton(
                                            onPressed: () => Get.toNamed(AppRoutes.STOCK_ENTRY_FORM, arguments: {'name': entry.name, 'mode': 'view'}),
                                            child: const Text('View'),
                                          ),
                                        ]
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
