import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/item/form/widgets/stock_balance_chart.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class ItemFormScreen extends GetView<ItemFormController> {
  const ItemFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isModal = Get.currentRoute != AppRoutes.ITEM_FORM;
    final cs = Theme.of(context).colorScheme;

    // Fix #1: use controller.tabController — lives in GetX, never reset by Obx.
    return Scaffold(
      appBar: MainAppBar(
        // Fix #2: Obx around title so it updates once item loads.
        title: '',
        titleWidget: Obx(
          () => Text(
            controller.item.value?.itemName ?? 'Item Details',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        leading: isModal
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: Get.back,
              )
            : null,
        bottom: TabBar(
          controller: controller.tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Stock Levels'),
            Tab(text: 'Attributes'),
            Tab(text: 'Attachments'),
          ],
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final item = controller.item.value;
        if (item == null) {
          return Center(
            child: _buildEmptyState(
              context,
              cs,
              icon: Icons.error_outline,
              message: 'Item not found.',
            ),
          );
        }

        return TabBarView(
          controller: controller.tabController,
          children: [
            _buildOverviewTab(context, item, cs),
            _buildStockLevelsTab(context, cs),
            _buildAttributesTab(context, item, cs),
            _buildAttachmentsTab(context, cs),
          ],
        );
      }),
    );
  }

  // ── Overview Tab ────────────────────────────────────────────────────────

  Widget _buildOverviewTab(BuildContext context, Item item, ColorScheme cs) {
    final String baseUrl = Get.find<ApiProvider>().baseUrl;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero image with loading shimmer (Fix #8)
          if (item.image != null)
            GestureDetector(
              onTap: () =>
                  _openFullScreenImage(context, '$baseUrl${item.image}'),
              child: Container(
                height: 200,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  // Fix #10: theme token instead of Colors.white
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Hero(
                  tag: 'item_image_${item.itemCode}',
                  child: Image.network(
                    '$baseUrl${item.image}',
                    fit: BoxFit.contain,
                    // Fix #8: shimmer placeholder during load
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                              : null,
                          color: cs.primary,
                          strokeWidth: 2,
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.image_not_supported_outlined,
                      size: 50,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),

          _buildSectionCard(
            context: context,
            cs: cs,
            title: 'General',
            children: [
              _buildDetailRow(
                context: context,
                cs: cs,
                label: 'Item Code',
                value: item.itemCode,
                isCopyable: true,
                onCopy: () => controller.copyToClipboard(item.itemCode),
              ),
              Divider(color: cs.outlineVariant),
              _buildDetailRow(
                  context: context,
                  cs: cs,
                  label: 'Item Name',
                  value: item.itemName),
              Divider(color: cs.outlineVariant),
              _buildDetailRow(
                  context: context,
                  cs: cs,
                  label: 'Item Group',
                  value: item.itemGroup),
            ],
          ),

          const SizedBox(height: 16),

          _buildSectionCard(
            context: context,
            cs: cs,
            title: 'Inventory',
            children: [
              _buildDetailRow(
                  context: context,
                  cs: cs,
                  label: 'Default UOM',
                  value: item.stockUom ?? '-'),
              if (item.countryOfOrigin != null) ...[
                Divider(color: cs.outlineVariant),
                _buildDetailRow(
                    context: context,
                    cs: cs,
                    label: 'Country of Origin',
                    value: item.countryOfOrigin!),
              ],
            ],
          ),

          if (item.variantOf != null || item.description != null) ...[
            const SizedBox(height: 16),
            _buildSectionCard(
              context: context,
              cs: cs,
              title: 'Description',
              children: [
                if (item.variantOf != null) ...[
                  _buildDetailRow(
                      context: context,
                      cs: cs,
                      label: 'Variant Of',
                      value: item.variantOf!),
                  Divider(color: cs.outlineVariant),
                ],
                if (item.description != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detailed Description',
                        // Fix #13/14: theme token
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.description!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurface, height: 1.4),
                      ),
                    ],
                  ),
              ],
            ),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ── Stock Levels Tab ────────────────────────────────────────────────────

  Widget _buildStockLevelsTab(BuildContext context, ColorScheme cs) {
    final theme = Theme.of(context);

    // Fix #16: RefreshIndicator for manual refresh
    return RefreshIndicator(
      onRefresh: controller.fetchDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Warehouse Balance Chart
            Text(
              'Warehouse Balance',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Obx(() {
              if (controller.isLoadingStock.value) {
                return const LinearProgressIndicator();
              }
              if (controller.stockLevels.isEmpty) {
                return _buildEmptyState(
                  context,
                  cs,
                  icon: Icons.warehouse_outlined,
                  message: 'No stock available in any warehouse.',
                );
              }
              return StockBalanceChart(stockLevels: controller.stockLevels);
            }),

            const SizedBox(height: 24),

            // 2. Batch-Wise Balance
            Text(
              'Batch-Wise Balance',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Obx(() {
              if (controller.isLoadingBatches.value) {
                return const LinearProgressIndicator();
              }
              if (controller.batchHistory.isEmpty) {
                return _buildEmptyState(
                  context,
                  cs,
                  icon: Icons.category_outlined,
                  message: 'No batch history found.',
                );
              }
              return Column(
                children: controller.batchHistory.map((batch) {
                  final dateStr = batch['stock_age_date'];
                  final ageString =
                      controller.getFormattedStockAge(dateStr);
                  final batchNo =
                      batch['batch_no'] ?? batch['batch'] ?? 'N/A';
                  final qty = batch['balance_qty'];
                  final warehouse = batch['warehouse'];

                  // Fix #10: theme tokens replace hardcoded white/grey
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                batchNo,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (warehouse != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  warehouse,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSecondaryContainer,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$qty ${controller.item.value?.stockUom ?? ''}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Age: $ageString',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.orange.shade700,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            }),

            const SizedBox(height: 24),

            // 3. Stock Ledger
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Stock Ledger',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
                Obx(() => IconButton(
                      icon: Icon(
                        Icons.calendar_month,
                        color: controller.ledgerDateRange.value != null
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange:
                              controller.ledgerDateRange.value,
                        );
                        if (picked != null) {
                          controller.updateLedgerDateRange(picked);
                        }
                      },
                    )),
              ],
            ),

            // Fix #17: d MMM yy format to include year
            Obx(() {
              final range = controller.ledgerDateRange.value;
              if (range == null) return const SizedBox.shrink();
              final fmt = DateFormat('d MMM yy');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Chip(
                  label: Text(
                      '${fmt.format(range.start)} – ${fmt.format(range.end)}'),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: controller.clearLedgerDateRange,
                  visualDensity: VisualDensity.compact,
                ),
              );
            }),

            Obx(() {
              if (controller.isLoadingLedger.value) {
                return const LinearProgressIndicator();
              }
              if (controller.stockLedgerEntries.isEmpty) {
                return _buildEmptyState(
                  context,
                  cs,
                  icon: Icons.receipt_long_outlined,
                  message: 'No transactions found in this period.',
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.stockLedgerEntries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = controller.stockLedgerEntries[index];
                  final qty =
                      (entry['actual_qty'] as num).toDouble();
                  final isPositive = qty > 0;

                  String subtitle = '${entry['voucher_no']}';
                  String? extraInfo;

                  if (entry['voucher_type'] == 'Delivery Note' &&
                      entry['customer'] != null) {
                    extraInfo = 'Customer: ${entry['customer']}';
                  } else if (entry['voucher_type'] == 'Stock Entry' &&
                      entry['stock_entry_type'] == 'Material Issue' &&
                      entry['custom_reference_no'] != null) {
                    extraInfo = 'Ref: ${entry['custom_reference_no']}';
                  }

                  // Fix #11: theme tokens replace Colors.white / grey.shade200
                  return Card(
                    elevation: 0,
                    color: cs.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry['voucher_type'],
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                '${isPositive ? '+' : ''}$qty',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(
                                  color: isPositive
                                      ? Colors.green.shade600
                                      : cs.error,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          if (extraInfo != null)
                            Text(
                              extraInfo,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.secondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              if (entry['warehouse'] != null)
                                Expanded(
                                  child: Text(
                                    entry['warehouse'],
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(
                                            color: cs.onSurfaceVariant),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              Text(
                                FormattingHelper.getRelativeTime(
                                    '${entry['posting_date']} '
                                    '${entry['posting_time']}'),
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(
                                        color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Attributes Tab ─────────────────────────────────────────────────────────

  Widget _buildAttributesTab(
      BuildContext context, Item item, ColorScheme cs) {
    final theme = Theme.of(context);

    if (item.attributes.isEmpty) {
      return Center(
        child: _buildEmptyState(
          context,
          cs,
          icon: Icons.list_alt_outlined,
          message: 'No attributes defined.',
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: item.attributes.length,
      separatorBuilder: (_, __) => Divider(color: cs.outlineVariant),
      itemBuilder: (context, index) {
        final attr = item.attributes[index];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          // Fix #12: theme tokens instead of hardcoded Colors.grey
          title: Text(
            attr.attributeName,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          trailing: Text(
            attr.attributeValue,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        );
      },
    );
  }

  // ── Attachments Tab ──────────────────────────────────────────────────────

  Widget _buildAttachmentsTab(BuildContext context, ColorScheme cs) {
    final theme = Theme.of(context);
    final String baseUrl = Get.find<ApiProvider>().baseUrl;

    return Obx(() {
      if (controller.attachments.isEmpty) {
        return Center(
          child: _buildEmptyState(
            context,
            cs,
            icon: Icons.attach_file_outlined,
            message: 'No attachments found.',
          ),
        );
      }

      // Fix #7: fully defined gridDelegate
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: controller.attachments.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.85,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (ctx, i) {
          final file = controller.attachments[i];
          final String fileUrl = file['file_url'] ?? '';
          final String fileName = file['file_name'] ?? 'Unknown';
          final bool isImg = controller.isImage(fileUrl);
          final String fullUrl = '$baseUrl$fileUrl';

          return Card(
            elevation: 0,
            color: cs.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (isImg) _openFullScreenImage(context, fullUrl);
                else controller.copyLink(fileUrl);
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: isImg
                        ? Image.network(
                            fullUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                color: cs.surfaceContainerHighest,
                                child: const Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              );
                            },
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.broken_image_outlined,
                              color: cs.onSurfaceVariant,
                            ),
                          )
                        : Icon(
                            Icons.insert_drive_file_outlined,
                            size: 48,
                            color: cs.primary,
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 4, 2),
                    child: Text(
                      fileName,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: Icon(Icons.share, size: 18,
                          color: cs.onSurfaceVariant),
                      onPressed: () =>
                          controller.shareFile(fileUrl, fileName),
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  // ── Shared helpers ─────────────────────────────────────────────────────────

  Widget _buildSectionCard({
    required BuildContext context,
    required ColorScheme cs,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    // Fix #13: theme tokens for section card
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required BuildContext context,
    required ColorScheme cs,
    required String label,
    required String value,
    bool isCopyable = false,
    VoidCallback? onCopy,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Fix #14: theme token instead of Colors.black54
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                // Fix #9: copy icon is now tappable
                if (isCopyable && onCopy != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onCopy,
                    child: Icon(
                      Icons.copy,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Fix #18: proper empty state with icon + centred layout
  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme cs, {
    required IconData icon,
    required String message,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: cs.outlineVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // Fix #15: swipe-down-to-dismiss + barrierDismissible
  void _openFullScreenImage(BuildContext context, String url) {
    Get.dialog(
      barrierDismissible: true,
      barrierColor: Colors.black87,
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          // Swipe down to dismiss
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 300) {
              Get.back();
            }
          },
          child: Stack(
            children: [
              InteractiveViewer(
                child: Center(
                  child: Image.network(
                    url,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: Get.back,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
