import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

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
      final status = controller.posUpload.value?.status;

      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: MainAppBar(
            title: title,
            status: status,
            bottom: const TabBar(
              tabs: [Tab(text: 'Details'), Tab(text: 'Items')],
            ),
          ),
          body: controller.isLoading.value
              ? const Center(child: CircularProgressIndicator())
              : controller.posUpload.value == null
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
                  : SafeArea(
                      child: TabBarView(
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

  // Cached permission flags (fix #6)
  late final bool _canEditStatus;
  late final bool _canEditAmount;
  late final bool _canEditQty;

  @override
  void initState() {
    super.initState();
    final ctrl = widget.controller;
    final upload = ctrl.posUpload.value;

    _amountCtrl = TextEditingController(
        text: PosUploadFormController.fmtAmount(upload?.totalAmount));
    _qtyCtrl = TextEditingController(
        text: PosUploadFormController.fmtQty(upload?.totalQty));

    // Cache permission flags once (fix #6)
    _canEditStatus = ctrl.canEditStatus;
    _canEditAmount = ctrl.canEditAmount;
    _canEditQty = ctrl.canEditQty;

    // Sync text controllers when the document is reloaded (fix #2)
    ever(ctrl.posUpload, (PosUpload? updated) {
      if (updated == null) return;
      if (!_amountCtrl.text.contains(updated.totalAmount?.toString() ?? '')) {
        _amountCtrl.text =
            PosUploadFormController.fmtAmount(updated.totalAmount);
      }
      _qtyCtrl.text = PosUploadFormController.fmtQty(updated.totalQty);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final cs = Theme.of(context).colorScheme;

    return Obx(() {
      final upload = ctrl.posUpload.value;
      if (upload == null) return const SizedBox.shrink();

      final canSave = _canEditStatus || _canEditAmount || _canEditQty;

      // ── Linked-doc banner ─────────────────────────────────────────────────
      Widget? linkedBanner;
      if (ctrl.isLoadingLinked.value) {
        linkedBanner = const _StatusBanner(
          icon: Icons.sync,
          color: Colors.orange,
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
          color: Colors.green,
          text:
              '${isDelivery ? 'Delivery Note' : 'Stock Entry'}: ${ctrl.linkedDocName.value}',
          trailing: const Icon(Icons.chevron_right, size: 16, color: Colors.green),
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
          psBanner = const _StatusBanner(
            icon: Icons.inventory_outlined,
            color: Colors.blue,
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
            color: Colors.indigo,
            text:
                '$psCount Packing Slip${psCount == 1 ? '' : 's'} · $psMatched / ${ctrl.resolvedSerials.length} items matched',
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

              // Fix #3 — status dropdown wired to updateStatus()
              DropdownButtonFormField<String>(
                value: upload.status,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Status',
                  border: const OutlineInputBorder(),
                  filled: !_canEditStatus,
                  fillColor: !_canEditStatus ? cs.surfaceContainerHighest : null,
                ),
                items: [
                  'Pending',
                  'In Progress',
                  'Cancelled',
                  'Draft',
                  'Submitted',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: _canEditStatus
                    ? (v) {
                        if (v != null) ctrl.updateStatus(v);
                      }
                    : null,
              ),
              const SizedBox(height: 16),

              // Fix #14 — formatted amounts
              TextFormField(
                controller: _amountCtrl,
                readOnly: !_canEditAmount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Total Amount',
                  border: const OutlineInputBorder(),
                  filled: !_canEditAmount,
                  fillColor:
                      !_canEditAmount ? cs.surfaceContainerHighest : null,
                  suffixIcon: !_canEditAmount
                      ? const Icon(Icons.lock, size: 16, color: Colors.grey)
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _qtyCtrl,
                readOnly: !_canEditQty,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Total Quantity',
                  border: const OutlineInputBorder(),
                  filled: !_canEditQty,
                  fillColor:
                      !_canEditQty ? cs.surfaceContainerHighest : null,
                  suffixIcon: !_canEditQty
                      ? const Icon(Icons.lock, size: 16, color: Colors.grey)
                      : null,
                ),
              ),
              const SizedBox(height: 24),

              if (canSave)
                Obx(() => SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: ctrl.isSaving.value
                            ? null
                            : () {
                                final data = <String, dynamic>{};
                                if (_canEditAmount) {
                                  // Strip formatting before parsing (fix #14)
                                  final raw = _amountCtrl.text
                                      .replaceAll(',', '');
                                  data['total_amount'] =
                                      double.tryParse(raw) ?? 0.0;
                                }
                                if (_canEditQty) {
                                  final raw =
                                      _qtyCtrl.text.replaceAll(',', '');
                                  data['total_qty'] =
                                      double.tryParse(raw) ?? 0.0;
                                }
                                if (data.isNotEmpty) {
                                  ctrl.updatePosUpload(data);
                                }
                              },
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(16)),
                        child: ctrl.isSaving.value
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white))
                            : const Text('Update',
                                style: TextStyle(fontSize: 16)),
                      ),
                    )),
            ],
          ),
        ),
      );
    });
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
              separatorBuilder: (_, __) => const SizedBox(width: 8),
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
                  label: Text(opt.label),
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

        // ── Progress summary strip (fix #11 — wrapped in Card surface) ────
        Obx(() {
          final isLoadingLinked = ctrl.isLoadingLinked.value;
          final isLoadingPS = ctrl.isLoadingPackingSlips.value;
          final linkedType = ctrl.linkedDocType.value;
          final hasLinkedDoc = ctrl.resolvedSerials.isNotEmpty;
          final hasPS = ctrl.resolvedPackingSlips.isNotEmpty;

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

          if (!hasLinkedDoc) return const SizedBox.shrink();

          final dnMatched = ctrl.resolvedSerials.values
              .where((v) => v != null && v.isNotEmpty)
              .length;
          final total = ctrl.resolvedSerials.length;
          final psMatchedCount = ctrl.resolvedPackingSlips.values
              .where((v) => v != null)
              .length;

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
              child: Wrap(
                spacing: 20,
                runSpacing: 4,
                children: [
                  _SummaryChip(
                    icon: linkedType == LinkedDocType.deliveryNote
                        ? Icons.local_shipping_outlined
                        : Icons.inventory_2_outlined,
                    label:
                        '$dnMatched / $total ${linkedType == LinkedDocType.deliveryNote ? 'DN' : 'SE'}',
                    color: dnMatched == total ? Colors.green : cs.primary,
                  ),
                  if (hasPS)
                    _SummaryChip(
                      icon: Icons.inventory_outlined,
                      label: '$psMatchedCount / $total PS',
                      color: psMatchedCount == total
                          ? Colors.green
                          : Colors.indigo,
                    ),
                  // Active filter indicator
                  if (ctrl.activeCaseFilter.value != null)
                    _SummaryChip(
                      icon: Icons.filter_list,
                      label: ctrl.activeCaseFilter.value!.label,
                      color: cs.tertiary,
                    ),
                ],
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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Obx(() => _ItemCard(
                        item: item,
                        // Fix #4 — O(1) display index from item.idx
                        displayIndex: item.idx,
                        isLoadingLinked: ctrl.isLoadingLinked.value,
                        isLoadingPS:
                            ctrl.isLoadingPackingSlips.value,
                        linkedDocType: ctrl.linkedDocType.value,
                        resolvedSerial: ctrl.resolvedSerials[item.idx],
                        packingSlipInfo:
                            ctrl.resolvedPackingSlips[item.idx],
                        hasLinkedDoc: ctrl.resolvedSerials.isNotEmpty,
                      ));
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

class _ItemCard extends StatelessWidget {
  final PosUploadItem item;
  final int displayIndex;
  final bool isLoadingLinked;
  final bool isLoadingPS;
  final LinkedDocType linkedDocType;
  final String? resolvedSerial;
  final PackingSlipInfo? packingSlipInfo;
  final bool hasLinkedDoc;

  const _ItemCard({
    required this.item,
    required this.displayIndex,
    required this.isLoadingLinked,
    required this.isLoadingPS,
    required this.linkedDocType,
    required this.resolvedSerial,
    required this.packingSlipInfo,
    required this.hasLinkedDoc,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ── Match status (fix #10 — visible label, not tooltip-only) ─────────
    final matchStatus = _resolveMatchStatus();

    // ── Chips ─────────────────────────────────────────────────────────────
    final chips = <Widget>[];

    if (resolvedSerial != null && resolvedSerial!.isNotEmpty) {
      chips.add(_InfoChip(
        icon: Icons.qr_code,
        label: resolvedSerial!,
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
      ));
    }

    if (isLoadingPS && linkedDocType == LinkedDocType.deliveryNote) {
      chips.add(_InfoChip(
        icon: Icons.hourglass_top_rounded,
        label: 'PS…',
        backgroundColor: Colors.blue.withValues(alpha: 0.12),
        foregroundColor: Colors.blue.shade700,
        isSpinner: true,
      ));
    } else if (packingSlipInfo != null) {
      final from = packingSlipInfo!.fromCaseNo;
      final to = packingSlipInfo!.toCaseNo;
      final caseLabel = (from != null && to != null)
          ? 'Cases $from – $to'
          : (from != null ? 'Case $from' : packingSlipInfo!.psName);
      chips.add(_InfoChip(
        icon: Icons.inventory_outlined,
        label: caseLabel,
        backgroundColor: Colors.indigo.withValues(alpha: 0.10),
        foregroundColor: Colors.indigo.shade700,
        tooltip: 'Packing Slip: ${packingSlipInfo!.psName}',
      ));
    } else if (!isLoadingPS &&
        linkedDocType == LinkedDocType.deliveryNote &&
        resolvedSerial != null &&
        resolvedSerial!.isNotEmpty) {
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      color: cs.surfaceContainerLowest,
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
                  radius: 13,
                  backgroundColor: cs.secondaryContainer,
                  child: Text(
                    '$displayIndex',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.itemName,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      // Fix #10 — visible status label below item name
                      if (matchStatus != null) ...[  
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(matchStatus.icon,
                                size: 12, color: matchStatus.color),
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
                _Stat(label: 'Qty', value: item.quantity.toString()),
                _Stat(
                    label: 'Rate',
                    value: PosUploadFormController.fmtAmount(item.rate)),
                _Stat(
                  label: 'Amount',
                  value:
                      PosUploadFormController.fmtAmount(item.amount),
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
          ],
        ),
      ),
    );
  }

  _MatchStatus? _resolveMatchStatus() {
    if (!hasLinkedDoc) return null;
    if (isLoadingLinked) {
      return _MatchStatus(
          icon: Icons.hourglass_top,
          label: 'Checking…',
          color: Colors.orange);
    }
    if (resolvedSerial != null && resolvedSerial!.isNotEmpty) {
      return _MatchStatus(
          icon: Icons.check_circle,
          label: 'Matched',
          color: Colors.green.shade700);
    }
    if (resolvedSerial != null) {
      return _MatchStatus(
          icon: Icons.check_circle_outline,
          label: 'Matched – no serial',
          color: Colors.teal.shade600);
    }
    return _MatchStatus(
        icon: Icons.cancel_outlined,
        label: 'Not found',
        color: Colors.red.shade600);
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
                color: highlight ? cs.primary : null,
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
