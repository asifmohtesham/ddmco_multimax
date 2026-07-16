/// Scheduled digest of documents needing action.
///
/// GetX-free by design: everything in this file also runs inside the
/// WorkManager background isolate (see digest_worker.dart) where no GetX
/// bindings exist.
library;

/// One doctype tracked by the digest.
class DigestDoctype {
  final String key; // pref key, e.g. 'purchase_order'
  final String doctype; // ERPNext DocType name
  final String singular; // copy after a count of 1
  final String plural; // copy after any other count
  final Map<String, dynamic> filters; // frappe.client.get_count filters

  const DigestDoctype({
    required this.key,
    required this.doctype,
    required this.singular,
    required this.plural,
    required this.filters,
  });
}

/// Registry order == notification body order.
const List<DigestDoctype> kDigestDoctypes = [
  DigestDoctype(
    key: 'purchase_order',
    doctype: 'Purchase Order',
    singular: 'draft Purchase Order',
    plural: 'draft Purchase Orders',
    filters: {'docstatus': 0},
  ),
  DigestDoctype(
    key: 'purchase_receipt',
    doctype: 'Purchase Receipt',
    singular: 'draft Purchase Receipt',
    plural: 'draft Purchase Receipts',
    filters: {'docstatus': 0},
  ),
  DigestDoctype(
    key: 'delivery_note',
    doctype: 'Delivery Note',
    singular: 'draft Delivery Note',
    plural: 'draft Delivery Notes',
    filters: {'docstatus': 0},
  ),
  DigestDoctype(
    key: 'stock_entry',
    doctype: 'Stock Entry',
    singular: 'draft Stock Entry',
    plural: 'draft Stock Entries',
    filters: {'docstatus': 0},
  ),
  DigestDoctype(
    key: 'pos_upload',
    doctype: 'POS Upload',
    singular: 'POS Upload to fulfil',
    plural: 'POS Uploads to fulfil',
    // The two statuses the app treats as open for fulfilment.
    filters: {
      'status': ['in', ['Pending', 'In Progress']],
    },
  ),
];

enum DigestStatus { ok, authExpired, failed }

class DigestResult {
  final DigestStatus status;

  /// key (from [DigestDoctype.key]) → server count. Only doctypes that were
  /// actually counted appear; permission-denied doctypes are absent.
  final Map<String, int> counts;

  DigestResult.ok(this.counts) : status = DigestStatus.ok;
  DigestResult.authExpired()
      : status = DigestStatus.authExpired,
        counts = const {};
  DigestResult.failed()
      : status = DigestStatus.failed,
        counts = const {};

  int get total => counts.values.fold(0, (a, b) => a + b);
}

/// What (if anything) to put on screen for a [DigestResult]. Pure — unit
/// tested; the plugin glue in digest_worker.dart stays trivially thin.
class DigestNotificationPlan {
  final bool show;
  final String? title;
  final String? body;

  const DigestNotificationPlan._({required this.show, this.title, this.body});

  static const none = DigestNotificationPlan._(show: false);

  static DigestNotificationPlan forResult(DigestResult r) {
    switch (r.status) {
      case DigestStatus.failed:
        return none; // never nag about our own failures
      case DigestStatus.authExpired:
        return const DigestNotificationPlan._(
          show: true,
          title: 'Session expired',
          body: 'Open Multimax to resume digests',
        );
      case DigestStatus.ok:
        if (r.total == 0) return none; // silent tick
        final clauses = kDigestDoctypes
            .where((d) => (r.counts[d.key] ?? 0) > 0)
            .map((d) {
          final c = r.counts[d.key]!;
          return '$c ${c == 1 ? d.singular : d.plural}';
        }).join(' · ');
        return DigestNotificationPlan._(
          show: true,
          title: 'Pending documents (${r.total})',
          body: clauses,
        );
    }
  }
}
