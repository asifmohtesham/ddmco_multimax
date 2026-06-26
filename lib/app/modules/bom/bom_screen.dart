import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/models/bom_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/bom/bom_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_shell_scaffold.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/app/modules/global_widgets/list_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';
import 'package:multimax/app/modules/global_widgets/report_filter_sheet.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/search_highlight.dart';

class BomScreen extends StatefulWidget {
  const BomScreen({super.key});

  @override
  State<BomScreen> createState() => _BomScreenState();
}

class _BomScreenState extends State<BomScreen> {
  final BomController controller = Get.find();
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
    if (!_scrollController.hasClients) return;
    final atBottom = _scrollController.offset >=
        _scrollController.position.maxScrollExtent * 0.9;
    if (atBottom &&
        controller.hasMore.value &&
        !controller.isFetchingMore.value) {
      controller.fetchBOMs(isLoadMore: true);
    }
  }

  void _showQuickWoSheet(BuildContext context, BOM bom) {
    Get.bottomSheet(
      _QuickWoSheet(bom: bom),
      isScrollControlled: true,
    );
  }

  List<Widget> _buildFilterChips(BuildContext context) {
    final chips = <Widget>[];

    // Routes through the shared FilterChipWidget so chip styling stays uniform
    // across every list screen.
    Widget chip({
      required IconData icon,
      required String label,
      required VoidCallback onDeleted,
    }) =>
        FilterChipWidget(icon: icon, label: label, onDeleted: onDeleted);

    if (controller.searchQuery.value.isNotEmpty) {
      chips.add(chip(
        icon: Icons.search,
        label: 'Search: ${controller.searchQuery.value}',
        onDeleted: () {
          controller.searchQuery.value = '';
          controller.fetchBOMs(clear: true);
        },
      ));
    }
    if (controller.activeFilters.containsKey('is_active')) {
      chips.add(chip(
        icon: Icons.check_circle_outline,
        label: 'Active only',
        onDeleted: () => controller.removeFilter('is_active'),
      ));
    }
    if (controller.activeFilters.containsKey('docstatus')) {
      chips.add(chip(
        icon: Icons.verified_outlined,
        label: 'Submitted',
        onDeleted: () => controller.removeFilter('docstatus'),
      ));
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenTitle = controller.pageTitle ?? 'Bill of Materials';

    return AppShellScaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed(
          AppRoutes.BOM_FORM,
          arguments: {'name': '', 'mode': 'new'},
        ),
        label: const Text('New BOM'),
        icon: const Icon(Icons.account_tree_outlined),
        tooltip: 'Create new Bill of Materials',
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.fetchBOMs(clear: true),
        color: cs.primary,
        backgroundColor: cs.surfaceContainerHighest,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            DocTypeListHeader(
              title: screenTitle,
              automaticallyImplyLeading: false,
              searchDoctype:      'BOM',
              searchQuery:        controller.searchQuery,
              onSearchChanged:    controller.onSearchChanged,
              onSearchClear:      controller.clearFilters,
              activeFilters:      controller.activeFilters,
              filterChipsBuilder: _buildFilterChips,
              onClearAllFilters:  controller.clearFilters,
              onFilterTap:        () => _showFilterSheet(context),
            ),

            Obx(() {
              if (controller.isLoading.value && controller.boms.isEmpty) {
                return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()));
              }

              if (controller.boms.isEmpty) {
                final hasFilters = controller.activeFilters.isNotEmpty ||
                    controller.searchQuery.value.isNotEmpty;
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: ListEmptyState(
                    hasActiveFilters: hasFilters,
                    emptyIcon: Icons.account_tree_outlined,
                    emptyTitle: 'No BOMs Found',
                    emptyMessage:
                        'Tap "+ New BOM" to create your first Bill of Materials.',
                    filteredTitle: 'No Matching BOMs',
                    filteredMessage:
                        'Try clearing the active filter to see all BOMs.',
                    onClearFilters: controller.clearFilters,
                    onReload: () => controller.fetchBOMs(clear: true),
                  ),
                );
              }

              // Capture query once — passed down to every card.
              final query = controller.searchQuery.value;
              final boms  = controller.boms;

              return SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: _BomKpiStrip(controller: controller),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          if (index >= boms.length) {
                            return ListEndFooter(
                                hasMore: controller.hasMore.value);
                          }
                          final bom = boms[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _BomCard(
                              bom: bom,
                              searchQuery: query,
                              onTap: () => Get.toNamed(
                                AppRoutes.BOM_FORM,
                                arguments: {'name': bom.name},
                              ),
                              onLongPress: () => _showQuickWoSheet(context, bom),
                              onCreateWo: () => Get.toNamed(
                                AppRoutes.WORK_ORDER_FORM,
                                arguments: {
                                  'mode': 'new',
                                  'name': '',
                                  'prefill': {
                                    'production_item': bom.item,
                                    'item_name':       bom.itemName ?? '',
                                    'bom_no':          bom.name,
                                    'qty':             bom.quantity,
                                  },
                                },
                              ),
                            ),
                          );
                        },
                        childCount: boms.length + 1,
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    // Activate the DataWedge worker before the sheet opens.
    controller.initBarcodeListener();

    showReportFilterSheet(
      context:     context,
      title:       'BOM Search Filters',
      fields:      [ /* 5 item code fields — unchanged */ ],
      controllers: controller.filterControllers,

      // ── NEW: chip groups appended below the scan-slot fields ──────────────
      chipGroups: [
        ReportFilterChipGroup(
          key:   'is_active',
          label: 'Status',
          options: const [
            ReportFilterChipOption(
              value: '1',
              label: 'Active',
              icon:  Icons.check_circle_outline,
            ),
          ],
        ),
        ReportFilterChipGroup(
          key:   'docstatus',
          label: 'Document Status',
          options: const [
            ReportFilterChipOption(
              value: '1',
              label: 'Submitted',
              icon:  Icons.verified_outlined,
            ),
          ],
        ),
      ],
      // ─────────────────────────────────────────────────────────────────────

      onRun: () {
        for (final key in BomController.scanSlotKeys) {
          final val = controller.filterControllers[key]!.text.trim();
          if (val.isNotEmpty) {
            controller.setFilter(key, val);
          } else {
            controller.removeFilter(key);
          }
        }
        // Propagate chip selections — same pattern as scan slots.
        final isActive = controller.filterControllers['is_active']!.text.trim();
        final docStatus = controller.filterControllers['docstatus']!.text.trim();
        if (isActive.isNotEmpty) {
          controller.setFilter('is_active', isActive);
        } else {
          controller.removeFilter('is_active');
        }
        if (docStatus.isNotEmpty) {
          controller.setFilter('docstatus', int.tryParse(docStatus) ?? docStatus);
        } else {
          controller.removeFilter('docstatus');
        }
      },
      onClear: () {
        controller.clearFilterControllers();
        controller.clearFilters();
      },
    ).then((_) => controller.disposeBarcodeListener());
  }
}

// ── Filter bottom sheet ─────────────────────────────────────────────────────────

class _BomFilterSheet extends StatelessWidget {
  final BomController controller;
  const _BomFilterSheet({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Filter BOMs',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                TextButton(
                  onPressed: () {
                    controller.clearFilters();
                    Navigator.pop(context);
                  },
                  child: const Text('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Status', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Obx(() {
              final isActiveOnly =
                  controller.activeFilters.containsKey('is_active');
              final isSubmitted =
                  controller.activeFilters.containsKey('docstatus');
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Active only'),
                    selected: isActiveOnly,
                    onSelected: (_) {
                      if (isActiveOnly) {
                        controller.removeFilter('is_active');
                      } else {
                        controller.setFilter('is_active', 1);
                      }
                      Navigator.pop(context);
                    },
                    avatar: Icon(Icons.check_circle_outline,
                        size: 16,
                        color: isActiveOnly
                            ? cs.onSecondaryContainer
                            : cs.onSurfaceVariant),
                  ),
                  ChoiceChip(
                    label: const Text('Submitted'),
                    selected: isSubmitted,
                    onSelected: (_) {
                      if (isSubmitted) {
                        controller.removeFilter('docstatus');
                      } else {
                        controller.setFilter('docstatus', 1);
                      }
                      Navigator.pop(context);
                    },
                    avatar: Icon(Icons.verified_outlined,
                        size: 16,
                        color: isSubmitted
                            ? cs.onSecondaryContainer
                            : cs.onSurfaceVariant),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── KPI strip ────────────────────────────────────────────────────────────────────

class _BomKpiStrip extends StatelessWidget {
  final BomController controller;
  const _BomKpiStrip({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _Kpi('Total',    '${controller.totalBoms}',                cs.primary),
          const SizedBox(width: 8),
          _Kpi('Active',
              '${(controller.activeRate * 100).toInt()}%',           cs.tertiary),
          const SizedBox(width: 8),
          _Kpi('Avg Cost',
              NumberFormat.compactSimpleCurrency()
                  .format(controller.averageCost),                    cs.secondary),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _Kpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── BOM card ──────────────────────────────────────────────────────────────────────

class _BomCard extends StatelessWidget {
  final BOM bom;
  final VoidCallback onTap;
  final VoidCallback onCreateWo;
  final VoidCallback onLongPress;
  /// Current search query — passed from the parent Obx to avoid extra rebuilds.
  final String searchQuery;

  const _BomCard({
    required this.bom,
    required this.onTap,
    required this.onCreateWo,
    required this.onLongPress,
    required this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final isActive = bom.isActive == 1;

    // Primary display text: prefer itemName, fall back to item code.
    final displayName =
        (bom.itemName?.isNotEmpty ?? false) ? bom.itemName! : bom.item;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive
              ? cs.primary.withValues(alpha: 0.25)
              : cs.outlineVariant,
        ),
      ),
      color: cs.surfaceContainerLowest,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isActive
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest,
                child: Icon(Icons.layers,
                    color: isActive
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item name — highlighted
                    SearchHighlight(
                      text: displayName,
                      query: searchQuery,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // BOM name (item code) — highlighted
                    SearchHighlight(
                      text: bom.name,
                      query: searchQuery,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${FormattingHelper.getCurrencySymbol(bom.currency ?? '')} '
                    '${NumberFormat('#,##0').format(bom.totalCost)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive
                              ? cs.tertiaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 10,
                            color: isActive
                                ? cs.onTertiaryContainer
                                : cs.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onCreateWo,
                        child: Tooltip(
                          message: 'Create Work Order',
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.precision_manufacturing_outlined,
                              size: 14,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick Work Order creation sheet ───────────────────────────────────────────

class _QuickWoSheet extends StatefulWidget {
  final BOM bom;
  const _QuickWoSheet({required this.bom});

  @override
  State<_QuickWoSheet> createState() => _QuickWoSheetState();
}

class _QuickWoSheetState extends State<_QuickWoSheet> {
  late final TextEditingController _qtyController;
  DateTime _startDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: widget.bom.quantity % 1 == 0
          ? widget.bom.quantity.toInt().toString()
          : widget.bom.quantity.toStringAsFixed(3),
    );
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  void _create() {
    final qty = double.tryParse(_qtyController.text) ?? widget.bom.quantity;
    Get.back();
    Get.toNamed(
      AppRoutes.WORK_ORDER_FORM,
      arguments: {
        'mode': 'new',
        'name': '',
        'prefill': {
          'production_item': widget.bom.item,
          'item_name':       widget.bom.itemName ?? '',
          'bom_no':          widget.bom.name,
          'qty':             qty,
          'planned_start_date': DateFormat('yyyy-MM-dd').format(_startDate),
        },
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mq   = MediaQuery.of(context);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, mq.viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Create Work Order', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            widget.bom.itemName?.isNotEmpty == true ? widget.bom.itemName! : widget.bom.item,
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Quantity',
              border: const OutlineInputBorder(),
              suffixText: widget.bom.uom ?? '',
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Start Date',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
              ),
              child: Text(DateFormat('dd MMM yyyy').format(_startDate)),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _create,
              child: const Text('Create Work Order'),
            ),
          ),
        ],
      ),
    );
  }
}
