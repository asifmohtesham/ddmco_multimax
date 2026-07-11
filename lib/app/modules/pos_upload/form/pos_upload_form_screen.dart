import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:share_plus/share_plus.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/realtime_sync_status_icon.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';
import 'package:multimax/app/modules/pos_upload/widgets/pos_upload_timeline.dart';

class PosUploadFormScreen extends GetView<PosUploadFormController> {
  const PosUploadFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Single outer Obx drives the AppBar title reactively (fix #5).
    return Obx(() {
      final title = controller.posUpload.value?.name.isNotEmpty == true
          ? controller.posUpload.value!.name
          : controller.name.isNotEmpty
              ? controller.name
              : 'POS Upload';
      final isLoading  = controller.isLoading.value;
      final posUpload  = controller.posUpload.value;
      // Gate on the loaded DN object (not linkedDocName): if the DN detail
      // fetch failed, deliveryNote stays null and the export stays disabled
      // instead of throwing when the sheet opens.
      final canShare = controller.deliveryNote.value != null ||
          controller.packingSlips.isNotEmpty;

      return DefaultTabController(
        length: 2,
        child: Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (ctx, _) => [
              DocTypeFormHeader(
                title:       title,
                docType:     'POS Upload',
                statusLabel: posUpload?.status,
                onShare: canShare ? () => _showShareSheet(context) : null,
                extraActions: [
                  RealtimeSyncStatusIcon(
                    isConnected: controller.isRealtimeConnected,
                    isSyncing:   controller.isRemoteSyncing,
                  ),
                ],
                bottom: const TabBar(
                  tabs: [Tab(text: 'Details'), Tab(text: 'Items')],
                ),
              ),
            ],
            body: isLoading
                ? const Center(child: CircularProgressIndicator())
                : posUpload == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                size: 48,
                                color: Theme.of(context).colorScheme.error),
                            const SizedBox(height: 12),
                            const Text('POS Upload not found.',
                                style: TextStyle(fontSize: 16)),
                          ],
                        ),
                      )
                    : TabBarView(
                        children: [
                          _DetailsTab(controller: controller),
                          _ItemsTab(controller: controller),
                        ],
                      ),
          ),
        ),
      );
    });
  }

  // Must match the column names in the controller's export builders
  // (_buildPackingSlipExcel / buildDeliveryNoteExcelBytes).
  static List<String> _columnNames(ExportDocType docType, bool compact) {
    // Ref Code resolves from the POS Upload items by invoice serial.
    final base = compact
        ? ['Invoice Serial #', 'Ref Code', 'Item Name', 'Qty', 'Country of Origin']
        : [
            'Invoice Serial #',
            'Ref Code',
            'Variant Of',
            'Item Code',
            'Item Name',
            'Qty',
            'Country of Origin',
          ];
    return docType == ExportDocType.packingSlip ? ['Case #', ...base] : base;
  }

  static const _shortLabels = {
    'Case #': 'Case',
    'Invoice Serial #': 'Serial',
    'Ref Code': 'Ref',
    'Variant Of': 'Variant',
    'Item Code': 'Code',
    'Item Name': 'Item',
    'Qty': 'Qty',
    'Country of Origin': 'Country',
  };

  void _showShareSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final hasDn = controller.deliveryNote.value != null;
        final hasPs = controller.packingSlips.isNotEmpty;
        // Default to the most-used export when available.
        var docType =
            hasPs ? ExportDocType.packingSlip : ExportDocType.deliveryNote;
        var compact = true;
        String? sortByColumn;
        var isExporting = false;
        return StatefulBuilder(
          builder: (ctx, setState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Export as Excel',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ExportDocType>(
                    segments: [
                      ButtonSegment(
                        value: ExportDocType.deliveryNote,
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('Delivery Note'),
                        enabled: hasDn,
                      ),
                      ButtonSegment(
                        value: ExportDocType.packingSlip,
                        icon: const Icon(Icons.inventory_outlined),
                        label: const Text('Packing Slip'),
                        enabled: hasPs,
                      ),
                    ],
                    selected: {docType},
                    onSelectionChanged: isExporting
                        ? null
                        : (selection) => setState(() {
                              docType = selection.first;
                              // Reset sort only if the column doesn't exist
                              // for the new doc type (Case # is PS-only).
                              if (sortByColumn != null &&
                                  !_columnNames(docType, compact)
                                      .contains(sortByColumn)) {
                                sortByColumn = null;
                              }
                            }),
                  ),
                  if (!hasPs || !hasDn) ...[
                    const SizedBox(height: 6),
                    Text(
                      !hasPs
                          ? 'No packing slips yet'
                          : 'Delivery note not available',
                      style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Compact'),
                    subtitle: Text(
                      _columnNames(docType, compact)
                          .map((c) => _shortLabels[c]!)
                          .join(' · '),
                    ),
                    value: compact,
                    onChanged: isExporting
                        ? null
                        : (v) => setState(() {
                              compact = v;
                              sortByColumn = null;
                            }),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    // ignore: deprecated_member_use
                    value: sortByColumn,
                    decoration: const InputDecoration(
                      labelText: 'Sort by',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('None (natural order)'),
                      ),
                      ..._columnNames(docType, compact).map(
                        (name) =>
                            DropdownMenuItem(value: name, child: Text(name)),
                      ),
                    ],
                    onChanged: isExporting
                        ? null
                        : (v) => setState(() => sortByColumn = v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: isExporting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(ctx).colorScheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.table_view_outlined),
                    label: Text(isExporting ? 'Exporting…' : 'Share as Excel'),
                    onPressed: isExporting
                        ? () {}
                        : () async {
                            setState(() => isExporting = true);
                            final docLabel =
                                docType == ExportDocType.packingSlip
                                    ? 'Packing Slip'
                                    : 'Delivery Note';
                            try {
                              final filePath =
                                  docType == ExportDocType.packingSlip
                                      ? await controller.buildPackingSlipExcel(
                                          compact: compact,
                                          sortByColumn: sortByColumn,
                                        )
                                      : await controller.buildDeliveryNoteExcel(
                                          compact: compact,
                                          sortByColumn: sortByColumn,
                                        );
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              await Share.shareXFiles(
                                [
                                  XFile(
                                    filePath,
                                    mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                                  ),
                                ],
                                subject:
                                    '${controller.posUpload.value?.name} – $docLabel',
                              );
                            } catch (e) {
                              if (ctx.mounted) {
                                setState(() => isExporting = false);
                              }
                              // GlobalSnackbar uses Get's global overlay, not
                              // ctx — safe even after the sheet was popped
                              // (e.g. Share.shareXFiles throws post-pop).
                              GlobalSnackbar.error(
                                  message: 'Export failed: $e');
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Details Tab
// ─────────────────────────────────────────────────────────────────────────────

class _DetailsTab extends StatefulWidget {
  final PosUploadFormController controller;
  const _DetailsTab({required this.controller});

  @override
  State<_DetailsTab> createState() => _DetailsTabState();
}

class _DetailsTabState extends State<_DetailsTab> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _qtyCtrl;
  late final Worker _posUploadWorker;

  /// All possible status values a POS Upload can have.
  /// Must be kept in sync with ERPNext so the DropdownButtonFormField
  /// never receives a value that isn't in this list (prevents assertion crash).
  static const _statusOptions = [
    'Draft',
    'Pending',
    'In Progress',
    'Completed',
    'Cancelled',
    'Submitted',
  ];

  @override
  void initState() {
    super.initState();
    final ctrl = widget.controller;
    final upload = ctrl.posUpload.value;

    _amountCtrl = TextEditingController(
        text: PosUploadFormController.fmtAmount(upload?.totalAmount));
    _qtyCtrl = TextEditingController(
        text: PosUploadFormController.fmtQty(upload?.totalQty));

    // Sync text controllers when the document is reloaded (fix #2)
    _posUploadWorker = ever(ctrl.posUpload, (PosUpload? updated) {
      if (updated == null) return;
      _amountCtrl.text = PosUploadFormController.fmtAmount(updated.totalAmount);
      _qtyCtrl.text = PosUploadFormController.fmtQty(updated.totalQty);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _qtyCtrl.dispose();
    _posUploadWorker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final upload = ctrl.posUpload.value;
      if (upload == null) return const SizedBox.shrink();

      // Ensure the current status is always present in the list so the
      // DropdownButtonFormField never throws an assertion error for an
      // unexpected value coming from the server (e.g. "Completed").
      final statusItems = {
        ...?(_statusOptions.contains(upload.status) ? null : [upload.status]),
        ..._statusOptions,
      }.toList();

      // ── Linked-doc banner ─────────────────────────────────────────────────
      // Status ramp inks (x700 light / x300 dark) — the x500 bases fall
      // below 4.5:1 as banner text on light surfaces.
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final orangeInk = isDark ? AppColors.orange300 : AppColors.orange700;
      final greenInk = isDark ? AppColors.green300 : AppColors.green700;
      final blueInk = isDark ? AppColors.blue300 : AppColors.blue700;
      Widget? linkedBanner;
      if (ctrl.isLoadingLinked.value) {
        linkedBanner = _StatusBanner(
          icon: Icons.sync,
          color: orangeInk,
          text: 'Fetching linked document…',
          isSpinning: true,
        );
      } else if (ctrl.linkedDocType.value != LinkedDocType.none &&
          ctrl.linkedDocName.value.isNotEmpty) {
        final isDelivery =
            ctrl.linkedDocType.value == LinkedDocType.deliveryNote;
        // Fix #9 — banner is tappable
        linkedBanner = _StatusBanner(
          icon: isDelivery
              ? Icons.local_shipping_outlined
              : Icons.inventory_2_outlined,
          color: greenInk,
          text:
              '${isDelivery ? 'Delivery Note' : 'Stock Entry'}: ${ctrl.linkedDocName.value}',
          trailing: Icon(Icons.chevron_right, size: 16, color: greenInk),
          onTap: () {
            // TODO: navigate to DN/SE form screen when route is wired
            GlobalSnackbar.info(
                message: 'Navigate to ${ctrl.linkedDocName.value}');
          },
        );
      }

      // ── Packing Slip banner ───────────────────────────────────────────────
      Widget? psBanner;
      if (ctrl.linkedDocType.value == LinkedDocType.deliveryNote) {
        if (ctrl.isLoadingPackingSlips.value) {
          psBanner = _StatusBanner(
            icon: Icons.inventory_outlined,
            color: blueInk,
            text: 'Loading Packing Slips…',
            isSpinning: true,
          );
        } else if (ctrl.packingSlips.isNotEmpty) {
          final psCount = ctrl.packingSlips.length;
          final psMatched = ctrl.resolvedPackingSlips.values
              .where((v) => v != null)
              .length;
          psBanner = _StatusBanner(
            icon: Icons.inventory_outlined,
            color: cs.secondary,
            text:
                '$psCount Packing Slip${psCount == 1 ? '' : 's'} · $psMatched / ${ctrl.resolvedSerials.length} items packed',
          );
        }
      }

      return RefreshIndicator(
        // Fix #12 — pull-to-refresh
        onRefresh: ctrl.reloadDocument,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (linkedBanner != null) ...[linkedBanner, const SizedBox(height: 8)],
              if (psBanner != null) ...[psBanner, const SizedBox(height: 16)],

              _ReadOnlyField(label: 'Name', value: upload.name),
              const SizedBox(height: 16),

              // Fix #13 — explicit fillColor on Customer field
              TextFormField(
                initialValue: upload.customer,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Customer',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                initialValue: upload.date,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
              ),
              const SizedBox(height: 16),

              // Status dropdown — value is always guaranteed to be in statusItems
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: upload.status,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Status',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                ),
                items: statusItems
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: null,
              ),
              const SizedBox(height: 16),

              // Fix #14 — formatted amounts
              TextFormField(
                controller: _amountCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Total Amount',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _qtyCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Total Quantity',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  suffixIcon: const Icon(Icons.lock, size: 16, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24),

              // ── Progress timeline ────────────────────────────────────────
              const Divider(height: 1),
              const SizedBox(height: 16),
              Text(
                'Progress',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              PosUploadTimeline(checkpoints: _buildCheckpoints(ctrl, upload)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );
    });
  }

  /// Reads the controller's linked-doc / packing-slip state and produces the
  /// timeline checkpoints. Called inside the tab's [Obx] so every observable
  /// touched here re-triggers a rebuild.
  List<TimelineCheckpoint> _buildCheckpoints(
      PosUploadFormController ctrl, PosUpload upload) {
    final prefix =
        upload.name.length >= 2 ? upload.name.substring(0, 2).toUpperCase() : '';
    final isStockEntryUpload = prefix == 'MX' || prefix == 'KX';

    final slips = ctrl.packingSlips;
    final earliestPsCreation = slips.isEmpty
        ? null
        : slips
            .map((p) => p.creation)
            .where((c) => c.isNotEmpty)
            .fold<String?>(null, (min, c) =>
                (min == null || c.compareTo(min) < 0) ? c : min);

    final hasLinkedDoc = isStockEntryUpload
        ? (ctrl.linkedDocType.value == LinkedDocType.stockEntry &&
            ctrl.linkedDocName.value.isNotEmpty)
        : ctrl.deliveryNote.value != null;

    return buildPosUploadTimeline(
      isStockEntryUpload: isStockEntryUpload,
      posUploadCreation: upload.creation,
      itemCount: upload.items.length,
      isLoadingLinked: ctrl.isLoadingLinked.value,
      hasLinkedDoc: hasLinkedDoc,
      linkedDocName: ctrl.linkedDocName.value,
      linkedDocCreation: ctrl.linkedDocCreation.value,
      orderedQty: upload.totalQty,
      deliveredQty: ctrl.deliveryNote.value?.totalQty,
      isLoadingPackingSlips: ctrl.isLoadingPackingSlips.value,
      packingSlipCount: slips.length,
      earliestPackingSlipCreation: earliestPsCreation,
      packedItems:
          ctrl.resolvedPackingSlips.values.where((v) => v != null).length,
      totalSerials: ctrl.resolvedSerials.length,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Items Tab
// ─────────────────────────────────────────────────────────────────────────────

class _ItemsTab extends StatefulWidget {
  final PosUploadFormController controller;
  const _ItemsTab({required this.controller});

  @override
  State<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<_ItemsTab> {
  // Fix #8 — own TextEditingController for the search field
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ── Search bar with clear button (fix #8) ───────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Obx(() => TextField(
                controller: _searchCtrl,
                onChanged: ctrl.filterByText,
                decoration: InputDecoration(
                  labelText: 'Search Items',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: ctrl.searchQuery.value.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchCtrl.clear();
                            ctrl.filterByText('');
                          },
                        )
                      : null,
                ),
              )),
        ),

        // ── Case filter chips (ML/KA only, fix NEW) ──────────────────────────
        Obx(() {
          final options = ctrl.caseOptions;
          if (options.isEmpty) return const SizedBox.shrink();
          final active = ctrl.activeCaseFilter.value;
          return SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: options.length + 1, // +1 for "All" chip
              separatorBuilder: (context, i) => i == 0
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          height: 26,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const SizedBox(width: 8),
                      ],
                    )
                  : const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i == 0) {
                  // "All" chip
                  final isAll = active == null;
                  return FilterChip(
                    label: const Text('All Cases'),
                    selected: isAll,
                    onSelected: (_) => ctrl.filterByCase(null),
                    selectedColor: cs.primaryContainer,
                    checkmarkColor: cs.onPrimaryContainer,
                    labelStyle: TextStyle(
                      color: isAll
                          ? cs.onPrimaryContainer
                          : cs.onSurfaceVariant,
                      fontWeight:
                          isAll ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                }
                final opt = options[i - 1];
                final isSelected = active == opt;
                return FilterChip(
                  avatar: Icon(
                    Icons.inventory_outlined,
                    size: 14,
                    color: isSelected
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                  label: Text('${opt.label} • ${PosUploadFormController.fmtQty(opt.totalQty)}'),
                  selected: isSelected,
                  onSelected: (_) =>
                      ctrl.filterByCase(isSelected ? null : opt),
                  selectedColor: cs.primaryContainer,
                  checkmarkColor: cs.onPrimaryContainer,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                );
              },
            ),
          );
        }),

        // ── Progress summary strip ─────────────────────────────────────────────
        Obx(() {
          final isLoadingLinked = ctrl.isLoadingLinked.value;
          final isLoadingPS = ctrl.isLoadingPackingSlips.value;
          final linkedType = ctrl.linkedDocType.value;

          if (isLoadingLinked || isLoadingPS) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoadingLinked
                        ? 'Fetching ${linkedType == LinkedDocType.deliveryNote ? 'Delivery Note' : 'Stock Entry'}…'
                        : 'Fetching Packing Slips…',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                      borderRadius: BorderRadius.circular(4)),
                ],
              ),
            );
          }

          final activeCase = ctrl.activeCaseFilter.value;
          if (activeCase == null) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: _SummaryChip(
                icon: Icons.inventory_outlined,
                label: activeCase.label,
                color: cs.tertiary,
              ),
            ),
          );
        }),

        // ── List ──────────────────────────────────────────────────────────
        Expanded(
          child: Obx(() {
            final items = ctrl.filteredItems;
            final allItems = ctrl.posUpload.value?.items ?? [];
            final hasSearch = ctrl.searchQuery.value.isNotEmpty;
            final hasCase = ctrl.activeCaseFilter.value != null;

            // Fix #7 — rich empty states
            if (items.isEmpty) {
              if (allItems.isEmpty) {
                return const _EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No items',
                  subtitle: 'This POS Upload has no line items.',
                );
              }
              if (hasCase && hasSearch) {
                return _EmptyState(
                  icon: Icons.search_off,
                  title: 'No results',
                  subtitle:
                      'No items match "${ctrl.searchQuery.value}" in ${ctrl.activeCaseFilter.value!.label}.',
                  actionLabel: 'Clear filters',
                  onAction: ctrl.clearFilters,
                );
              }
              if (hasCase) {
                return _EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'No items in ${ctrl.activeCaseFilter.value!.label}',
                  subtitle:
                      'Try selecting a different case or remove the filter.',
                  actionLabel: 'Show all',
                  onAction: () => ctrl.filterByCase(null),
                );
              }
              return _EmptyState(
                icon: Icons.search_off,
                title: 'No results',
                subtitle:
                    'No items match "${ctrl.searchQuery.value}".',
                actionLabel: 'Clear search',
                onAction: () {
                  _searchCtrl.clear();
                  ctrl.filterByText('');
                },
              );
            }

            return RefreshIndicator(
              // Fix #12 — pull-to-refresh
              onRefresh: ctrl.reloadDocument,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                    16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Obx(() {
                        final allPsItems = ctrl.resolvedPsItems[item.idx] ?? [];
                        final cf = ctrl.activeCaseFilter.value;
                        final visiblePsItems = cf == null
                            ? allPsItems
                            : allPsItems
                                .where((e) => e.psName == cf.psName)
                                .toList();
                        return _ItemCard(
                          key: ValueKey(item.idx),
                          item: item,
                          displayIndex: item.idx,
                          isLoadingLinked: ctrl.isLoadingLinked.value,
                          isLoadingPS: ctrl.isLoadingPackingSlips.value,
                          linkedDocType: ctrl.linkedDocType.value,
                          resolvedSerial: ctrl.resolvedSerials[item.idx],
                          packingSlipInfo: ctrl.resolvedPackingSlips[item.idx],
                          hasLinkedDoc: ctrl.resolvedSerials.isNotEmpty,
                          dnQty: ctrl.resolvedDnQty[item.idx],
                          psItems: visiblePsItems,
                        );
                      });
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Item Card  — Fix #1: typed PosUploadItem, no more dynamic
// ─────────────────────────────────────────────────────────────────────────────

class _ItemCard extends StatefulWidget {
  final PosUploadItem item;
  final int displayIndex;
  final bool isLoadingLinked;
  final bool isLoadingPS;
  final LinkedDocType linkedDocType;
  final String? resolvedSerial;
  final PackingSlipInfo? packingSlipInfo;
  final bool hasLinkedDoc;
  final double? dnQty;
  final List<PsItemEntry> psItems;

  const _ItemCard({
    super.key,
    required this.item,
    required this.displayIndex,
    required this.isLoadingLinked,
    required this.isLoadingPS,
    required this.linkedDocType,
    required this.resolvedSerial,
    required this.packingSlipInfo,
    required this.hasLinkedDoc,
    required this.dnQty,
    required this.psItems,
  });

  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _expanded = false;

  @override
  void didUpdateWidget(_ItemCard old) {
    super.didUpdateWidget(old);
    if (old.psItems.isNotEmpty && widget.psItems.isEmpty) {
      _expanded = false;
    }
  }

  bool get _showProgressBar =>
      widget.resolvedSerial != null &&
      widget.resolvedSerial!.isNotEmpty &&
      !widget.isLoadingPS &&
      widget.psItems.isNotEmpty;

  double get _packedQty =>
      widget.psItems.fold(0.0, (s, e) => s + e.item.qty);

  double? _progressRatioFor(double packedQty) {
    final dq = widget.dnQty;
    if (dq == null || dq == 0) return null;
    return (packedQty / dq).clamp(0.0, 1.0);
  }

  String _progressLabelFor(double packedQty) {
    final packed = PosUploadFormController.fmtQty(packedQty);
    final dq = widget.dnQty;
    final total = (dq != null && dq > 0)
        ? PosUploadFormController.fmtQty(dq)
        : '–';
    return '$packed Packed / $total DN Qty';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final matchStatus = _resolveMatchStatus();
    final packedQty = _showProgressBar ? _packedQty : 0.0;

    final chips = <Widget>[];

    if (widget.resolvedSerial != null && widget.resolvedSerial!.isNotEmpty) {
      chips.add(_InfoChip(
        icon: Icons.tag,
        label: '#${widget.resolvedSerial!}',
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        tooltip: 'Invoice serial: ${widget.resolvedSerial!}',
      ));
    }

    if (widget.isLoadingPS && widget.linkedDocType == LinkedDocType.deliveryNote) {
      chips.add(_InfoChip(
        icon: Icons.hourglass_top_rounded,
        label: 'PS…',
        backgroundColor: Colors.blue.withValues(alpha: 0.12),
        foregroundColor: Colors.blue.shade700,
        isSpinner: true,
      ));
    } else if (widget.packingSlipInfo != null) {
      final from = widget.packingSlipInfo!.fromCaseNo;
      final to = widget.packingSlipInfo!.toCaseNo;
      final caseLabel = (from != null && to != null)
          ? 'Cases $from – $to'
          : (from != null ? 'Case $from' : widget.packingSlipInfo!.psName);
      chips.add(_InfoChip(
        icon: Icons.inventory_outlined,
        label: caseLabel,
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
        tooltip: 'Packing Slip: ${widget.packingSlipInfo!.psName}',
      ));
    } else if (!widget.isLoadingPS &&
        widget.linkedDocType == LinkedDocType.deliveryNote &&
        widget.resolvedSerial != null &&
        widget.resolvedSerial!.isNotEmpty) {
      chips.add(_InfoChip(
        icon: Icons.inventory_outlined,
        label: 'No PS',
        backgroundColor: cs.errorContainer,
        foregroundColor: cs.onErrorContainer,
        tooltip: 'No matching Packing Slip found',
      ));
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      color: cs.surfaceContainerLowest,
      child: InkWell(
        onTap: widget.psItems.isNotEmpty
            ? () => setState(() => _expanded = !_expanded)
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 10,
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      '${widget.displayIndex}',
                      style: TextStyle(
                        fontSize: 9,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                widget.item.itemName,
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (widget.psItems.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              AnimatedRotation(
                                turns: _expanded ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  Icons.expand_more,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (_showProgressBar) ...[
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: _progressRatioFor(packedQty),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _progressLabelFor(packedQty),
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ] else if (matchStatus != null) ...[
                          // Falls through to matchStatus (e.g. "Matched") while PS is loading
                          // or when psItems is empty for this item.
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(matchStatus.icon, size: 12, color: matchStatus.color),
                              const SizedBox(width: 3),
                              Text(
                                matchStatus.label,
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: matchStatus.color),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // ── Stats ────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Stat(
                    label: 'Qty',
                    value: PosUploadFormController.fmtQty(widget.item.quantity),
                  ),
                  _Stat(
                      label: 'Rate',
                      value: PosUploadFormController.fmtAmount(widget.item.rate)),
                  _Stat(
                    label: 'Amount',
                    value: PosUploadFormController.fmtAmount(widget.item.amount),
                    highlight: true,
                    colorScheme: cs,
                  ),
                ],
              ),

              // ── Chips ────────────────────────────────────────────────────
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: chips),
              ],

              // ── Expanded PS items panel ─────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? _buildPsItemsPanel(context)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPsItemsPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < widget.psItems.length; i++) ...[
            if (i > 0) const Divider(height: 16, thickness: 0.5),
            _buildPsItemRow(context, widget.psItems[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildPsItemRow(BuildContext context, PsItemEntry entry) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final psItem = entry.item;

    final String caseLabel;
    if (entry.fromCaseNo != null && entry.toCaseNo != null) {
      caseLabel = 'Cases ${entry.fromCaseNo} – ${entry.toCaseNo}';
    } else if (entry.fromCaseNo != null) {
      caseLabel = 'Case ${entry.fromCaseNo}';
    } else {
      caseLabel = entry.psName;
    }

    final subParts = <String>[psItem.itemCode];
    if (psItem.customVariantOf != null && psItem.customVariantOf!.isNotEmpty) {
      subParts.add(psItem.customVariantOf!);
    }
    if (psItem.customCountryOfOrigin != null &&
        psItem.customCountryOfOrigin!.isNotEmpty) {
      subParts.add(psItem.customCountryOfOrigin!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Case chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            caseLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Item name + qty
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                psItem.itemName,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              PosUploadFormController.fmtQty(psItem.qty),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.tertiary),
            ),
          ],
        ),
        // Subline: code · variant · country
        Text(
          subParts.join(' · '),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  _MatchStatus? _resolveMatchStatus() {
    if (!widget.hasLinkedDoc) return null;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (widget.isLoadingLinked) {
      return _MatchStatus(
          icon: Icons.hourglass_top,
          label: 'Checking…',
          color: isDark ? AppColors.orange300 : AppColors.orange700);
    }
    if (widget.resolvedSerial != null && widget.resolvedSerial!.isNotEmpty) {
      return _MatchStatus(
          icon: Icons.check_circle,
          label: 'Matched',
          color: isDark ? AppColors.green300 : AppColors.green700);
    }
    if (widget.resolvedSerial != null) {
      return _MatchStatus(
          icon: Icons.check_circle_outline,
          label: 'Matched – no serial',
          color: isDark ? AppColors.cyan300 : AppColors.cyan700);
    }
    return _MatchStatus(
        icon: Icons.cancel_outlined,
        label: 'Not found',
        color: isDark ? AppColors.red300 : AppColors.red700);
  }
}

class _MatchStatus {
  final IconData icon;
  final String label;
  final Color color;
  const _MatchStatus(
      {required this.icon, required this.label, required this.color});
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State  (fix #7)
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final String? tooltip;
  final bool isSpinner;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.tooltip,
    this.isSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget iconWidget = isSpinner
        ? SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: foregroundColor),
          )
        : Icon(icon, size: 13, color: foregroundColor);

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return tooltip != null
        ? Tooltip(message: tooltip!, child: chip)
        : chip;
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SummaryChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final ColorScheme? colorScheme;
  const _Stat({
    required this.label,
    required this.value,
    this.highlight = false,
    this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme ?? Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.onSurfaceVariant)),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: highlight ? cs.tertiary : null,
              ),
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool isSpinning;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.text,
    this.isSpinning = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          isSpinning
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: color))
              : Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    return onTap != null
        ? InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: content)
        : content;
  }
}
