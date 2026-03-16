import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/main_app_bar.dart';
import 'package:multimax/app/modules/pos_upload/form/pos_upload_form_controller.dart';

class PosUploadFormScreen extends GetView<PosUploadFormController> {
  const PosUploadFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Obx(() {
        final title = controller.posUpload.value?.name.isNotEmpty == true
            ? controller.posUpload.value!.name
            : controller.name.isNotEmpty
                ? controller.name
                : 'POS Upload';
        final status = controller.posUpload.value?.status;

        return Scaffold(
          appBar: MainAppBar(
            title: title,
            status: status,
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Details'),
                Tab(text: 'Items'),
              ],
            ),
          ),
          body: Obx(() {
            if (controller.isLoading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            final upload = controller.posUpload.value;
            if (upload == null) {
              return const Center(child: Text('POS Upload not found.'));
            }
            return SafeArea(
              child: TabBarView(
                children: [
                  _DetailsTab(controller: controller),
                  _ItemsTab(controller: controller),
                ],
              ),
            );
          }),
        );
      }),
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

  @override
  void initState() {
    super.initState();
    final upload = widget.controller.posUpload.value;
    _amountCtrl =
        TextEditingController(text: upload?.totalAmount?.toString() ?? '0.0');
    _qtyCtrl =
        TextEditingController(text: upload?.totalQty?.toString() ?? '0');
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
    return Obx(() {
      final upload = ctrl.posUpload.value;
      if (upload == null) return const SizedBox.shrink();

      final canEditStatus = ctrl.canEdit('status');
      final canEditAmount = ctrl.canEdit('total_amount');
      final canEditQty = ctrl.canEdit('total_qty');
      final canSave = canEditStatus || canEditAmount || canEditQty;

      // ── Linked-document banner ────────────────────────────────────────────
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
        final docLabel =
            ctrl.linkedDocType.value == LinkedDocType.deliveryNote
                ? 'Delivery Note'
                : 'Stock Entry';
        linkedBanner = _StatusBanner(
          icon: ctrl.linkedDocType.value == LinkedDocType.deliveryNote
              ? Icons.local_shipping_outlined
              : Icons.inventory_2_outlined,
          color: Colors.green,
          text: '$docLabel: ${ctrl.linkedDocName.value}',
        );
      }

      // ── Packing Slip banner (ML/KA only) ─────────────────────────────────
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
                '$psCount Packing Slip${psCount == 1 ? '' : 's'} · $psMatched item${psMatched == 1 ? '' : 's'} matched',
          );
        }
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (linkedBanner != null) ...[linkedBanner, const SizedBox(height: 8)],
            if (psBanner != null) ...[psBanner, const SizedBox(height: 16)],

            _ReadOnlyField(label: 'Name', value: upload.name),
            const SizedBox(height: 16),

            TextFormField(
              initialValue: upload.customer,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Customer',
                border: OutlineInputBorder(),
                filled: true,
                prefixIcon: Icon(Icons.person_outline),
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

            DropdownButtonFormField<String>(
              value: upload.status,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Status',
                border: const OutlineInputBorder(),
                filled: !canEditStatus,
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
              onChanged: canEditStatus ? (_) {} : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _amountCtrl,
              readOnly: !canEditAmount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Total Amount',
                border: const OutlineInputBorder(),
                filled: !canEditAmount,
                suffixIcon: !canEditAmount
                    ? const Icon(Icons.lock, size: 16, color: Colors.grey)
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _qtyCtrl,
              readOnly: !canEditQty,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Total Quantity',
                border: const OutlineInputBorder(),
                filled: !canEditQty,
                suffixIcon: !canEditQty
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
                              if (canEditAmount) {
                                data['total_amount'] =
                                    double.tryParse(_amountCtrl.text) ??
                                        0.0;
                              }
                              if (canEditQty) {
                                data['total_qty'] =
                                    double.tryParse(_qtyCtrl.text) ?? 0.0;
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
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Update',
                              style: TextStyle(fontSize: 16)),
                    ),
                  )),
          ],
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Items Tab
// ─────────────────────────────────────────────────────────────────────────────

class _ItemsTab extends StatelessWidget {
  final PosUploadFormController controller;
  const _ItemsTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: controller.filterItems,
            decoration: const InputDecoration(
              labelText: 'Search Items',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),

        // ── Progress summary strip ──────────────────────────────────────────
        Obx(() {
          final isLoadingLinked = controller.isLoadingLinked.value;
          final isLoadingPS = controller.isLoadingPackingSlips.value;
          final linkedType = controller.linkedDocType.value;
          final hasLinkedDoc = controller.resolvedSerials.isNotEmpty;
          final hasPS = controller.resolvedPackingSlips.isNotEmpty;

          // Still loading something — show linear progress
          if (isLoadingLinked || isLoadingPS) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLoadingLinked)
                    Text(
                      'Fetching ${linkedType == LinkedDocType.deliveryNote ? 'Delivery Note' : 'Stock Entry'}…',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  if (isLoadingPS)
                    Text(
                      'Fetching Packing Slips…',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            );
          }

          if (!hasLinkedDoc) return const SizedBox.shrink();

          final cs = Theme.of(context).colorScheme;
          final dnMatched = controller.resolvedSerials.values
              .where((v) => v != null && v.isNotEmpty)
              .length;
          final total = controller.resolvedSerials.length;

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _SummaryChip(
                  icon: linkedType == LinkedDocType.deliveryNote
                      ? Icons.local_shipping_outlined
                      : Icons.inventory_2_outlined,
                  label:
                      '$dnMatched / $total ${linkedType == LinkedDocType.deliveryNote ? 'DN' : 'SE'} matched',
                  color: cs.primary,
                ),
                if (hasPS)
                  _SummaryChip(
                    icon: Icons.inventory_outlined,
                    label:
                        '${controller.resolvedPackingSlips.values.where((v) => v != null).length} / $total PS matched',
                    color: Colors.indigo,
                  ),
              ],
            ),
          );
        }),

        Expanded(
          child: Obx(() {
            final items = controller.filteredItems;
            if (items.isEmpty) {
              return const Center(child: Text('No items found.'));
            }
            return ListView.separated(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = items[index];
                final originalIdx =
                    controller.posUpload.value!.items.indexOf(item);
                return Obx(() => _ItemCard(
                      item: item,
                      displayIndex: originalIdx + 1,
                      isLoadingLinked: controller.isLoadingLinked.value,
                      isLoadingPS:
                          controller.isLoadingPackingSlips.value,
                      linkedDocType: controller.linkedDocType.value,
                      resolvedSerial:
                          controller.resolvedSerials[item.idx],
                      packingSlipInfo:
                          controller.resolvedPackingSlips[item.idx],
                      hasLinkedDoc:
                          controller.resolvedSerials.isNotEmpty,
                    ));
              },
            );
          }),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Item Card
// ─────────────────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final dynamic item; // PosUploadItem
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

    // ── DN/SE progress badge (top-right of card header) ───────────────────
    Widget progressBadge;
    if (linkedDocType == LinkedDocType.none && !isLoadingLinked) {
      progressBadge = const SizedBox.shrink();
    } else if (isLoadingLinked) {
      progressBadge = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: cs.outline),
      );
    } else if (!hasLinkedDoc) {
      progressBadge = const SizedBox.shrink();
    } else if (resolvedSerial != null && resolvedSerial!.isNotEmpty) {
      progressBadge = Tooltip(
        message: resolvedSerial!,
        child: Icon(Icons.check_circle, color: cs.primary, size: 20),
      );
    } else if (resolvedSerial != null) {
      progressBadge = Tooltip(
        message: 'Matched — no serial assigned',
        child:
            Icon(Icons.check_circle_outline, color: cs.tertiary, size: 20),
      );
    } else {
      progressBadge = Tooltip(
        message: 'Not found in linked document',
        child: Icon(Icons.cancel_outlined, color: cs.error, size: 20),
      );
    }

    // ── Chips row (serial + case range) ──────────────────────────────────
    final chips = <Widget>[];

    // Serial chip
    if (resolvedSerial != null && resolvedSerial!.isNotEmpty) {
      chips.add(_InfoChip(
        icon: Icons.qr_code,
        label: resolvedSerial!,
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer,
      ));
    }

    // Packing Slip case-range chip
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
      // Serial found in DN but not in any PS
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
            // ── Header row ──────────────────────────────────────────────
            Row(
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
                  child: Text(
                    item.itemName,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                progressBadge,
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ── Stats row ───────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Stat(label: 'Qty', value: item.quantity.toString()),
                _Stat(
                    label: 'Rate',
                    value: item.rate.toStringAsFixed(2)),
                _Stat(
                  label: 'Amount',
                  value: item.amount.toStringAsFixed(2),
                  highlight: true,
                  colorScheme: cs,
                ),
              ],
            ),

            // ── Chips ────────────────────────────────────────────────────
            if (chips.isNotEmpty) ...
              [
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: chips),
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
        fillColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool isSpinning;

  const _StatusBanner({
    required this.icon,
    required this.color,
    required this.text,
    this.isSpinning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
        ],
      ),
    );
  }
}
