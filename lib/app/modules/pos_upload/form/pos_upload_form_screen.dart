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
        // Resolve title reactively so AppBar never hangs on 'Loading...'
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

      // ── Linked-document banner ────────────────────────────────────────
      Widget? linkedBanner;
      if (ctrl.isLoadingLinked.value) {
        linkedBanner = _LinkedBanner(
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
        linkedBanner = _LinkedBanner(
          icon: ctrl.linkedDocType.value == LinkedDocType.deliveryNote
              ? Icons.local_shipping_outlined
              : Icons.inventory_2_outlined,
          color: Colors.green,
          text: '$docLabel: ${ctrl.linkedDocName.value}',
          isSpinning: false,
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (linkedBanner != null) ...[linkedBanner, const SizedBox(height: 16)],

            _ReadOnlyField(label: 'Name', value: upload.name),
            const SizedBox(height: 16),

            // Customer (read-only; real Link field shown as plain text)
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

            // Status
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
                'Submitted'
              ]
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s)))
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
                                    double.tryParse(_amountCtrl.text) ?? 0.0;
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
                                  strokeWidth: 2,
                                  color: Colors.white))
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

        // Linked-doc loading strip
        Obx(() {
          if (controller.isLoadingLinked.value) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: LinearProgressIndicator(
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }
          if (controller.linkedDocType.value != LinkedDocType.none &&
              controller.linkedDocName.value.isNotEmpty) {
            final matched = controller.resolvedSerials.values
                .where((v) => v != null && v.isNotEmpty)
                .length;
            final total = controller.resolvedSerials.length;
            final colorScheme = Theme.of(context).colorScheme;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    '$matched / $total items matched',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
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
                final originalIdx = controller.posUpload.value!.items
                    .indexOf(item);
                return Obx(() => _ItemCard(
                      item: item,
                      displayIndex: originalIdx + 1,
                      isLoadingLinked: controller.isLoadingLinked.value,
                      linkedDocType: controller.linkedDocType.value,
                      resolvedSerial:
                          controller.resolvedSerials[item.idx],
                      hasLinkedDoc: controller.resolvedSerials.isNotEmpty,
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
  final LinkedDocType linkedDocType;
  final String? resolvedSerial; // null = no match, '' = matched but no serial
  final bool hasLinkedDoc;

  const _ItemCard({
    required this.item,
    required this.displayIndex,
    required this.isLoadingLinked,
    required this.linkedDocType,
    required this.resolvedSerial,
    required this.hasLinkedDoc,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // ── Progress badge ────────────────────────────────────────────────────
    Widget progressBadge;
    if (linkedDocType == LinkedDocType.none && !isLoadingLinked) {
      progressBadge = const SizedBox.shrink();
    } else if (isLoadingLinked) {
      progressBadge = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorScheme.outline,
        ),
      );
    } else if (!hasLinkedDoc) {
      progressBadge = const SizedBox.shrink();
    } else if (resolvedSerial != null && resolvedSerial!.isNotEmpty) {
      // Fully matched with a serial number
      progressBadge = Tooltip(
        message: resolvedSerial!,
        child: Icon(Icons.check_circle,
            color: colorScheme.primary, size: 20),
      );
    } else if (resolvedSerial != null) {
      // Row matched but serial is empty
      progressBadge = Tooltip(
        message: 'Matched — no serial assigned',
        child: Icon(Icons.check_circle_outline,
            color: colorScheme.tertiary, size: 20),
      );
    } else {
      // No matching row in linked doc
      progressBadge = Tooltip(
        message: 'Not found in linked document',
        child:
            Icon(Icons.cancel_outlined, color: colorScheme.error, size: 20),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      color: colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: colorScheme.secondaryContainer,
                  child: Text(
                    '$displayIndex',
                    style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold),
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
                    colorScheme: colorScheme),
              ],
            ),
            // Serial number chip (shown only when matched)
            if (resolvedSerial != null && resolvedSerial!.isNotEmpty) ...
              [
                const SizedBox(height: 8),
                Chip(
                  avatar: Icon(Icons.qr_code,
                      size: 14, color: colorScheme.onSecondaryContainer),
                  label: Text(
                    resolvedSerial!,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer),
                  ),
                  backgroundColor: colorScheme.secondaryContainer,
                  side: BorderSide.none,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────

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

class _LinkedBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final bool isSpinning;

  const _LinkedBanner({
    required this.icon,
    required this.color,
    required this.text,
    required this.isSpinning,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
