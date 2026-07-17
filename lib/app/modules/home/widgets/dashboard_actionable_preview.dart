import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// One previewed document row. [onTap] deep-links to that document's form.
class ActionableDocRowData {
  final String name;
  final String subtitle;
  final VoidCallback? onTap;
  const ActionableDocRowData({
    required this.name,
    required this.subtitle,
    this.onTap,
  });
}

/// Resolves an owner email to a display label: the user's full name when known,
/// otherwise the email's local part ('jawwad@x.com' -> 'jawwad'). Frappe stores
/// `owner` as an email; [namesByEmail] comes from the dashboard's loaded users,
/// which will not contain every owner under the Everyone scope.
String ownerLabelFor(String email, Map<String, String> namesByEmail) {
  if (email.isEmpty) return '';
  final name = namesByEmail[email];
  if (name != null && name.isNotEmpty) return name;
  final at = email.indexOf('@');
  return at > 0 ? email.substring(0, at) : email;
}

/// Short human date ('12 Jul'); empty when absent or unparseable.
String _shortDate(String raw) {
  if (raw.isEmpty) return '';
  final d = DateTime.tryParse(raw);
  return d == null ? '' : DateFormat('d MMM').format(d);
}

/// Maps a raw Frappe list row to a preview row for [doctype].
///
/// Every previewed document is a Draft (that IS the actionable definition), so
/// no status is rendered — the subtitle is `<party> · <owner> · <date>` with
/// empty segments omitted. Packing Slip has no posting_date on its list, so it
/// falls back to `creation`.
ActionableDocRowData docRowFor(
  String doctype,
  Map<String, dynamic> json,
  String Function(String) ownerLabel, {
  VoidCallback? onTap,
}) {
  String s(String key) => (json[key] ?? '').toString();

  String party;
  String date;
  switch (doctype) {
    case 'Purchase Order':
      party = s('supplier');
      date = _shortDate(s('transaction_date'));
      break;
    case 'Purchase Receipt':
      party = s('supplier');
      date = _shortDate(s('posting_date'));
      break;
    case 'Stock Entry':
      party = s('stock_entry_type');
      date = _shortDate(s('posting_date'));
      break;
    case 'Delivery Note':
      party = s('customer');
      date = _shortDate(s('posting_date'));
      break;
    case 'Packing Slip':
      party = s('delivery_note');
      date = _shortDate(s('creation'));
      break;
    default:
      party = '';
      date = _shortDate(s('creation'));
  }

  final segments = [party, ownerLabel(s('owner')), date]
      .where((p) => p.isNotEmpty)
      .toList();

  return ActionableDocRowData(
    name: s('name'),
    subtitle: segments.join(' · '),
    onTap: onTap,
  );
}

/// A single previewed document: id + `party · owner · date` + chevron.
class ActionableDocRow extends StatelessWidget {
  final ActionableDocRowData data;
  const ActionableDocRow({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    return Material(
      color: scheme.fg,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: scheme.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: scheme.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (data.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        data.subtitle,
                        style: TextStyle(fontSize: 12, color: scheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.textSubtle, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// The selected chip's document preview: up to three rows then a View All
/// button. Shows a skeleton while [isLoading]; collapses when there is nothing
/// to show.
class ActionableDocPreview extends StatelessWidget {
  final List<ActionableDocRowData> rows;
  final bool isLoading;
  final VoidCallback onViewAll;
  const ActionableDocPreview({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    if (isLoading) {
      return Column(
        key: const ValueKey('actionable-preview-loading'),
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 9),
            Container(
              height: 58,
              decoration: BoxDecoration(
                color: scheme.subtle,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: scheme.border),
              ),
            ),
          ],
        ],
      );
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 9),
          ActionableDocRow(data: rows[i]),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onViewAll,
            child: const Text('View All'),
          ),
        ),
      ],
    );
  }
}
