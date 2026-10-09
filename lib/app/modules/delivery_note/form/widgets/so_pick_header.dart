import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/delivery_note/form/so_pick.dart';

/// Top of the DN Items tab while picking against a Sales Order: which order,
/// for whom, how far along, and what to do next — readable at arm's length.
class SoPickHeader extends StatelessWidget {
  final SoPickContext order;
  final SoPickProgress progress;
  final bool isEditable;

  /// Linked POS Upload (Sales Voucher), shown beside the order number.
  final String? uploadName;

  const SoPickHeader({
    super.key,
    required this.order,
    required this.progress,
    required this.isEditable,
    this.uploadName,
  });

  static String _qty(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final done = progress.isComplete;
    final accent = done
        ? (isDark ? AppColors.green300 : AppColors.green700)
        : scheme.primary;
    final barFill = done ? AppColors.green500 : scheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.fg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 18, color: scheme.textSubtle),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  uploadName == null ? order.name : '${order.name} · $uploadName',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.textMuted,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Text(
                '${progress.completeLines}/${progress.totalLines} lines',
                key: const Key('so_pick_lines'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            order.customerName?.isNotEmpty == true
                ? order.customerName!
                : order.customer,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: scheme.text,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 8,
              backgroundColor: scheme.subtle,
              valueColor: AlwaysStoppedAnimation(barFill),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                done
                    ? Icons.check_circle_rounded
                    : Icons.qr_code_scanner_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  !isEditable
                      ? 'Picked ${_qty(progress.pickedQty)} of ${_qty(progress.pendingQty)}'
                      : done
                          ? 'Everything on this order is picked'
                          : 'Scan an item from this order · '
                              '${_qty(progress.pickedQty)} of ${_qty(progress.pendingQty)} picked',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: done ? accent : scheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Explains how the order's POS Upload stands for this DN, and — when an
/// upload arrived after picking began — offers the voucher-line assignment.
class SoUploadLinkBanner extends StatelessWidget {
  final SoUploadLink link;
  final String? soPoNo;
  final VoidCallback onAssign;

  const SoUploadLinkBanner({
    super.key,
    required this.link,
    required this.soPoNo,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (link) {
      case SoUploadLink.linked:
        return const SizedBox.shrink();
      case SoUploadLink.none:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: scheme.textSubtle),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'No POS Upload linked yet. Invoice serials are provisional '
                  'until it is.',
                  style: TextStyle(fontSize: 12.5, color: scheme.textMuted),
                ),
              ),
            ],
          ),
        );
      case SoUploadLink.wrongFamily:
        return _tint(
          context,
          base: AppColors.red500,
          ink: isDark ? AppColors.red300 : AppColors.red700,
          icon: Icons.error_outline,
          text: '$soPoNo is a Stock Entry upload (MX/KX) and cannot be '
              'delivered on a Delivery Note.',
        );
      case SoUploadLink.pendingAssignment:
        return _tint(
          context,
          base: AppColors.orange500,
          ink: isDark ? AppColors.orange300 : AppColors.orange700,
          icon: Icons.link,
          text: 'POS Upload $soPoNo is now linked to this order. Assign each '
              'picked row to its voucher line before scanning more.',
          action: FilledButton.icon(
            key: const Key('assign_voucher_lines'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.orange700,
              foregroundColor: Colors.white,
            ),
            onPressed: onAssign,
            icon: const Icon(Icons.playlist_add_check, size: 18),
            label: const Text('Assign voucher lines'),
          ),
        );
    }
  }

  Widget _tint(BuildContext context,
      {required Color base,
      required Color ink,
      required IconData icon,
      required String text,
      Widget? action}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: base.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: ink)),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: action),
          ],
        ],
      ),
    );
  }
}
