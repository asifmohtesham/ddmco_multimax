/// The Status filter on the Purchase Receipt list.
///
/// The filter sheet offers lifecycle labels, and the list keeps the chosen
/// label in `activeFilters['status']` so the chip reads "Status: Submitted"
/// and tapping it reopens the sheet on that choice. Some labels are not
/// Purchase Receipt `status` values, so the label is translated into a server
/// filter only when the list is queried.
///
/// Purchase Receipt `status` options (ERPNext v15 and v16 alike): Draft,
/// Partly Billed, To Bill, Completed, Return, Return Issued, Cancelled,
/// Closed. "Submitted" is not one of them: a submitted receipt reads one of
/// the billing, return or Closed values.
library;

/// The choices the filter sheet offers, in display order.
const purchaseReceiptStatusChoices = <String>[
  'Draft',
  'Submitted',
  'Completed',
  'Cancelled',
];

/// Server filters for the labels that are not, or not only, a `status` value.
/// A label not listed here is sent as `status = label`.
const _statusLabelFilters = <String, Map<String, dynamic>>{
  'Draft': {'docstatus': 0},
  // Every submitted receipt, whatever its billing, return or closed state.
  'Submitted': {'docstatus': 1},
  'Cancelled': {'docstatus': 2},
};

/// Returns the filters to send to the server for the list's [activeFilters].
///
/// Replaces the `status` label with its server filter and leaves every other
/// filter as it is. [activeFilters] is not changed.
Map<String, dynamic> purchaseReceiptQueryFilters(
    Map<String, dynamic> activeFilters) {
  final query = Map<String, dynamic>.from(activeFilters);
  final status = query['status'];
  final mapped = status is String ? _statusLabelFilters[status] : null;
  if (mapped != null) {
    query.remove('status');
    query.addAll(mapped);
  }
  return query;
}
