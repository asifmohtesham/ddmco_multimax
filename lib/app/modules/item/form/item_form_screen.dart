import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/item/form/item_form_controller.dart';
import 'package:multimax/app/modules/item/form/item_tab_controller.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/item/form/widgets/stock_balance_chart.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/doctype_image_upload.dart';
import 'package:multimax/app/modules/global_widgets/doc_section_card.dart';
import 'package:multimax/app/modules/global_widgets/doc_detail_row.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/providers/warehouse_provider.dart';
import 'package:multimax/app/data/services/permission_service.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/item/form/widgets/reorder_rule_card.dart';
import 'package:multimax/app/modules/item/form/widgets/reorder_rule_sheet.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';

class ItemFormScreen extends GetView<ItemFormController> {
  const ItemFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isModal = Get.currentRoute != AppRoutes.ITEM_FORM;
    final cs = Theme.of(context).colorScheme;
    final tabCtrl = Get.find<ItemTabController>();

    return Obx(() {
      final item      = controller.item.value;
      final isLoading = controller.isLoading.value;

      return PopScope(
        canPop: !controller.isReorderDirty.value,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (await _confirmDiscard()) Get.back();
        },
        child: Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              DocTypeFormHeader(
                title:   item?.name ?? controller.itemCode,
                docType: 'Item',
                extraActions: isModal
                    ? [
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Close',
                          onPressed: () async {
                            if (await _confirmDiscard()) Get.back();
                          },
                        ),
                      ]
                    : null,
                bottom: TabBar(
                  controller: tabCtrl.tabController,
                  isScrollable: true,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Stock Levels'),
                    Tab(text: 'Attributes'),
                    Tab(text: 'Attachments'),
                    Tab(text: 'Re-order'),
                  ],
                ),
              ),
            ],
            body: (isLoading && item == null)
                ? const Center(child: CircularProgressIndicator())
                : item == null
                    ? Center(
                        child: const FormEmptyState(
                          icon: Icons.error_outline,
                          message: 'Item not found.',
                        ),
                      )
                    : TabBarView(
                        controller: tabCtrl.tabController,
                        children: [
                          _buildOverviewTab(context, item, cs),
                          _buildStockLevelsTab(context, cs),
                          _buildAttributesTab(context, item, cs),
                          _buildAttachmentsTab(context, cs),
                          _buildReorderTab(context, item, cs),
                        ],
                      ),
          ),
        ),
      );
    });
  }

  /// Confirms before discarding unsaved re-order rules. Returns true when the
  /// caller should proceed with closing.
  ///
  /// GlobalDialog.confirm returns null when dismissed by tapping outside, so
  /// only an explicit `true` discards — an accidental tap keeps the edits.
  Future<bool> _confirmDiscard() async {
    if (!controller.isReorderDirty.value) return true;
    final discard = await GlobalDialog.confirm(
      title: 'Discard changes?',
      message: 'Your re-order rules have not been saved.',
      confirmText: 'Discard',
      confirmColor: AppColors.red700,
      icon: Icons.warning_amber_outlined,
    );
    return discard == true;
  }

  // ── Overview Tab ──────────────────────────────────────────────────────────

  Widget _buildOverviewTab(BuildContext context, Item item, ColorScheme cs) {
    final String baseUrl = Get.find<ApiProvider>().baseUrl;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DocTypeImageUpload(
            doctype: 'Item',
            docname: item.itemCode,
            fieldname: 'image',
            imageUrl: item.image,
            baseUrl: baseUrl,
            onUploaded: () { controller.fetchItemDetails(); },
          ),

          DocSectionCard(
            title: 'General',
            children: [
              DocDetailRow(
                label: 'Item Code',
                value: item.itemCode,
                isCopyable: true,
                onCopy: () => controller.copyToClipboard(item.itemCode),
              ),
              Divider(color: cs.outlineVariant),
              DocDetailRow(label: 'Item Name', value: item.itemName),
              Divider(color: cs.outlineVariant),
              DocDetailRow(label: 'Item Group', value: item.itemGroup),
            ],
          ),

          DocSectionCard(
            title: 'Inventory',
            children: [
              DocDetailRow(label: 'Default UOM', value: item.stockUom ?? '-'),
              if (item.countryOfOrigin != null) ...[
                Divider(color: cs.outlineVariant),
                DocDetailRow(
                    label: 'Country of Origin',
                    value: item.countryOfOrigin!),
              ],
            ],
          ),

          if (item.variantOf != null || item.description != null) ...[
            DocSectionCard(
              title: 'Description',
              children: [
                if (item.variantOf != null) ...[
                  DocDetailRow(label: 'Variant Of', value: item.variantOf!),
                  Divider(color: cs.outlineVariant),
                ],
                if (item.description != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Detailed Description',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.description!,
                        style: Theme.of(context).textTheme.bodyMedium
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

  // ── Stock Levels Tab ──────────────────────────────────────────────────────

  Widget _buildStockLevelsTab(BuildContext context, ColorScheme cs) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: controller.fetchDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Warehouse filter chips ────────────────────────────────────
            Obx(() {
              final warehouses = controller.availableWarehouses;
              if (controller.isLoadingStock.value || warehouses.length <= 1) {
                return const SizedBox.shrink();
              }
              final selected = controller.selectedWarehouse.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filter by Warehouse',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SelectableFilterChip(
                            label: 'All',
                            selected: selected == null,
                            onSelected: (_) =>
                                controller.clearWarehouseFilter(),
                          ),
                        ),
                        ...warehouses.map((wh) {
                          final isActive = selected == wh;
                          final label = wh.contains(' - ')
                              ? wh.split(' - ').first.trim()
                              : wh;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SelectableFilterChip(
                              label: label,
                              selected: isActive,
                              onSelected: (_) =>
                                  controller.onWarehouseChanged(wh),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              );
            }),

            // 1. Stock Balance
            Text(
              'Stock Balance',
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
              final levels = controller.filteredStockLevels;
              if (levels.isEmpty) {
                return FormEmptyState(
                  icon: Icons.warehouse_outlined,
                  message: controller.selectedWarehouse.value != null
                      ? 'No stock in the selected warehouse.'
                      : 'No stock available in any warehouse.',
                );
              }
              return StockBalanceChart(
                key: ValueKey(controller.selectedWarehouse.value),
                stockLevels: levels,
              );
            }),

            const SizedBox(height: 24),

            // 2. Batch-Wise Balance History
            Text(
              'Batch-Wise Balance History',
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
              final batches = controller.filteredBatchHistory;
              if (batches.isEmpty) {
                return FormEmptyState(
                  icon: Icons.category_outlined,
                  message: controller.selectedWarehouse.value != null
                      ? 'No batches in the selected warehouse.'
                      : 'No batch history found.',
                );
              }
              return Container(
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: batches.asMap().entries.map((entry) {
                    final isLast = entry.key == batches.length - 1;
                    final batch = entry.value;
                    final dateStr = batch['stock_age_date'];
                    final ageString = controller.getFormattedStockAge(dateStr);
                    final batchNo = batch['batch_no'] ?? batch['batch'] ?? 'N/A';
                    final rawQty = batch['balance_qty'];
                    final uom = controller.item.value?.stockUom ?? '';
                    final qtyFormatted = rawQty != null
                        ? NumberFormat('#,##0.##').format(
                            rawQty is num ? rawQty : num.tryParse(rawQty.toString()) ?? 0)
                        : '—';
                    final warehouse = batch['warehouse'];
                    final isHighlighted = ItemFormController.isBatchHighlighted(
                        batchNo, controller.highlightedBatchNo.value);

                    return Container(
                      decoration: BoxDecoration(
                        color: isHighlighted
                            ? cs.primaryContainer.withValues(alpha: 0.35)
                            : null,
                        border: Border(
                          bottom: isLast
                              ? BorderSide.none
                              : BorderSide(color: cs.outlineVariant),
                          left: isHighlighted
                              ? BorderSide(color: cs.primary, width: 3)
                              : BorderSide.none,
                        ),
                      ),
                      padding: EdgeInsets.only(
                        left: isHighlighted ? 9 : 12,
                        right: 12,
                        top: 10,
                        bottom: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 13, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  batchNo,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (warehouse != null) ...[
                                      Text(
                                        warehouse,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '  ·  ',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    Flexible(
                                      child: Text(
                                        ageString,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.orange.shade700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '$qtyFormatted $uom',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
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
                          initialDateRange: controller.ledgerDateRange.value,
                        );
                        if (picked != null) {
                          controller.updateLedgerDateRange(picked);
                        }
                      },
                    )),
              ],
            ),

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
                return const FormEmptyState(
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
                  final qty = (entry['actual_qty'] as num).toDouble();
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                entry['voucher_type'],
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              Text(
                                '${isPositive ? '+' : ''}$qty',
                                style: theme.textTheme.bodyMedium?.copyWith(
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (entry['warehouse'] != null)
                                Expanded(
                                  child: Text(
                                    entry['warehouse'],
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: cs.onSurfaceVariant),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              Text(
                                FormattingHelper.getRelativeTime(
                                    '${entry['posting_date']} '
                                    '${entry['posting_time']}'),
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: cs.onSurfaceVariant),
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

  // ── Attributes Tab ────────────────────────────────────────────────────────

  Widget _buildAttributesTab(BuildContext context, Item item, ColorScheme cs) {
    final theme = Theme.of(context);

    if (item.attributes.isEmpty) {
      return Center(
        child: const FormEmptyState(
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

  // ── Attachments Tab ───────────────────────────────────────────────────────

  Widget _buildAttachmentsTab(BuildContext context, ColorScheme cs) {
    final theme = Theme.of(context);
    final String baseUrl = Get.find<ApiProvider>().baseUrl;

    return Obx(() {
      if (controller.attachments.isEmpty) {
        return Center(
          child: const FormEmptyState(
            icon: Icons.attach_file_outlined,
            message: 'No attachments found.',
          ),
        );
      }

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

  // ── Shared helpers ────────────────────────────────────────────────────────

  void _openFullScreenImage(BuildContext context, String url) {
    Get.dialog(
      barrierDismissible: true,
      barrierColor: Colors.black87,
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
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

  // ── Re-order Tab ──────────────────────────────────────────────────────────

  /// Loads warehouses for the rule sheet's pickers.
  ///
  /// Filters mirror erpnext item.js:449-473 — group warehouses for
  /// "Check in (group)", leaf warehouses for "Request for".
  Future<List<String>> _loadWarehouses({required bool isGroup}) async {
    try {
      final response =
          await Get.find<WarehouseProvider>().getWarehouses(isGroup: isGroup);
      if (response.statusCode == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((w) => w['name'].toString())
            .toList();
      }
    } catch (_) {
      // Picker opens empty rather than throwing over the sheet.
    }
    return const [];
  }

  void _openRuleSheet(BuildContext context, {int? index}) {
    final isNew = index == null;
    final initial =
        isNew ? controller.newReorderRowTemplate() : controller.reorderRows[index];

    Get.bottomSheet(
      ReorderRuleSheet(
        initial: initial,
        loadWarehouses: _loadWarehouses,
        onSaved: (row) => isNew
            ? controller.addReorderRow(row)
            : controller.updateReorderRow(index, row),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildReorderTab(BuildContext context, Item item, ColorScheme cs) {
    final scheme = context.scheme;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Desk gates the section on `depends_on: "is_stock_item"`. The tab count
    // stays static at 5 — resizing a TabController built on
    // GetSingleTickerProviderStateMixin is fragile (see item_tab_controller.dart)
    // — so a non-stock item gets an empty state instead of a vanishing tab.
    if (!item.isStockItem) {
      return Center(
        child: const FormEmptyState(
          icon: Icons.inventory_2_outlined,
          message: 'Auto re-order applies to stock items only.',
        ),
      );
    }

    return Column(
      children: [
        // auto_indent defaults to 0 in v15, in which case these rules never
        // raise a Material Request. Desk only warns on save; warn always.
        Obx(() => InlineBanner(
              visible: !controller.autoIndentEnabled.value,
              message: 'Auto re-order is disabled in Stock Settings. '
                  'These rules will not raise Material Requests.',
              type: BannerType.warning,
            )),
        Expanded(
          child: Obx(() {
            final rows = controller.reorderRows;
            final canWrite =
                Get.find<PermissionService>().hasAccess('Item', permType: 'write') ??
                    false;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DocSectionCard(
                    title: 'Auto re-order',
                    children: [
                      Text(
                        'Reorder level based on Warehouse',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.textMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // "overrridden" is misspelled in the ERPNext source;
                        // kept verbatim.
                        'Will also apply for variants unless overrridden',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.textSubtle),
                      ),
                      const SizedBox(height: 12),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No re-order rules. Nothing will be re-ordered '
                            'automatically for this item.',
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: scheme.textMuted),
                          ),
                        ),
                      ...rows.asMap().entries.map(
                            (e) => ReorderRuleCard(
                              rule: e.value,
                              index: e.key,
                              onEdit: canWrite
                                  ? () => _openRuleSheet(context, index: e.key)
                                  : null,
                              onDelete: canWrite
                                  ? () => controller.removeReorderRow(e.key)
                                  : null,
                            ),
                          ),
                      DocTypeGuard(
                        doctype: 'Item',
                        permType: 'write',
                        fallback: const SizedBox.shrink(),
                        loading: const SizedBox.shrink(),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _openRuleSheet(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Add rule'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Mirrors the Desk description: a variant with no rules of
                  // its own falls back to the template's at scheduler time.
                  // Stored rows only are shown — inheritance is computed
                  // server-side in memory and never persisted, so rendering the
                  // template's rows here would misrepresent stored state.
                  if (item.variantOf != null && rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        'No rules of its own. The template\'s rules apply '
                        'unless you add rules here.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.textSubtle),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        // The save bar appears only when there is something to save, so the
        // button is never enabled-but-inert. AsyncFilledButton requires a
        // non-null onPressed, so visibility is the disable mechanism.
        Obx(() {
          if (!controller.isReorderDirty.value) return const SizedBox.shrink();
          return DocTypeGuard(
            doctype: 'Item',
            permType: 'write',
            fallback: const SizedBox.shrink(),
            loading: const SizedBox.shrink(),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
              decoration: BoxDecoration(
                color: scheme.fg,
                border: Border(
                    top: BorderSide(color: cs.outlineVariant)),
              ),
              child: AsyncFilledButton(
                busy: controller.isSavingReorder,
                onPressed: controller.saveReorderLevels,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: 'Save re-order rules',
                loadingLabel: 'Saving…',
              ),
            ),
          );
        }),
      ],
    );
  }
}
