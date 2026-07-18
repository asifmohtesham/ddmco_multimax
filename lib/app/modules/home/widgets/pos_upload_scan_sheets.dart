import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';

/// Bottom sheet shown when a Delivery-Note-family POS Upload (ML/KA) is scanned
/// on the Dashboard: it asks the operator whether to open the linked Delivery
/// Note or its Packing Slip. Stock-Entry-family uploads (MX/KX) never reach
/// this sheet — they open the Stock Entry directly.
class PosUploadScanTargetSheet extends StatelessWidget {
  final PosUpload posUpload;
  final VoidCallback onDeliveryNote;
  final VoidCallback onPackingSlip;

  const PosUploadScanTargetSheet({
    super.key,
    required this.posUpload,
    required this.onDeliveryNote,
    required this.onPackingSlip,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: scheme.fg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: scheme.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('POS Upload',
                style: TextStyle(color: scheme.textMuted, fontSize: 12)),
            const SizedBox(height: 2),
            Text(
              posUpload.name,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (posUpload.customer.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(posUpload.customer,
                  style: TextStyle(color: scheme.textMuted, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            Text('Open which document?',
                style: TextStyle(
                    color: scheme.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _TargetOption(
              icon: Icons.local_shipping_outlined,
              label: 'Delivery Note',
              subtitle: 'View or continue the delivery',
              onTap: onDeliveryNote,
            ),
            const SizedBox(height: 12),
            _TargetOption(
              icon: Icons.assignment_outlined,
              label: 'Packing Slip',
              subtitle: 'Pack cartons against the delivery',
              onTap: onPackingSlip,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _TargetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _TargetOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final primary = Theme.of(context).primaryColor;
    return Material(
      color: scheme.subtle,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            color: scheme.text,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            TextStyle(color: scheme.textMuted, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.textSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown when a scanned POS Upload's Delivery Note has more than
/// one Packing Slip (one per case/carton): the operator picks which slip to
/// open, or starts a new case.
class PackingSlipPickerSheet extends StatelessWidget {
  final String deliveryNote;
  final int nextCaseNo;
  final List<Map<String, dynamic>> packingSlips;
  final void Function(String psName) onSelect;
  final VoidCallback onNewCase;

  const PackingSlipPickerSheet({
    super.key,
    required this.deliveryNote,
    required this.nextCaseNo,
    required this.packingSlips,
    required this.onSelect,
    required this.onNewCase,
  });

  String _caseLabel(Map<String, dynamic> ps) {
    final from = (ps['from_case_no'] as num?)?.toInt();
    final to = (ps['to_case_no'] as num?)?.toInt();
    if (from == null) return '';
    if (to == null || to == from) return 'Case $from';
    return 'Cases $from–$to';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.fg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      child: SafeArea(
        child: DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Packing Slips',
                                style: TextStyle(
                                    color: scheme.textMuted, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text(deliveryNote,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                        style:
                            IconButton.styleFrom(backgroundColor: scheme.subtle),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16.0),
                    itemCount: packingSlips.length + 1,
                    separatorBuilder: (c, i) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _PickerRow(
                          leading: Icons.add,
                          title: 'Start new case (#$nextCaseNo)',
                          subtitle: 'Create a new Packing Slip',
                          emphasise: true,
                          onTap: onNewCase,
                        );
                      }
                      final ps = packingSlips[index - 1];
                      final name = ps['name']?.toString() ?? '';
                      return _PickerRow(
                        leading: Icons.assignment_outlined,
                        title: _caseLabel(ps).isEmpty ? name : _caseLabel(ps),
                        subtitle: name,
                        onTap: () => onSelect(name),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final IconData leading;
  final String title;
  final String subtitle;
  final bool emphasise;
  final VoidCallback onTap;

  const _PickerRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final primary = Theme.of(context).primaryColor;
    return Material(
      color: scheme.subtle,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(leading, color: emphasise ? primary : scheme.textMuted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: emphasise ? primary : scheme.text,
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: TextStyle(
                            color: scheme.textMuted,
                            fontSize: 12,
                            fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.textSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
