/// The Status filter on the Delivery Note list.
///
/// The filter sheet offers lifecycle labels, and the list keeps the chosen
/// label in `activeFilters['status']` so the chip reads "Status: Submitted"
/// and tapping it reopens the sheet on that choice. Some labels are not
/// Delivery Note `status` values, so the label is translated into a server
/// filter only when the list is queried.
///
/// Delivery Note `status` options (ERPNext v15 and v16 alike): Draft, To Bill,
/// Partially Billed, Completed, Return, Return Issued, Cancelled, Closed.
/// "Submitted" is not one of them, and "Return" is set only on a submitted
/// return that has not been billed; a billed return reads "Completed".
library;

/// The choices the filter sheet offers, in display order.
const deliveryNoteStatusChoices = <String>[
  'Draft',
  'Submitted',
  'Return',
  'Completed',
  'Cancelled',
];

/// Server filters for the labels that are not a `status` value. A label not
/// listed here is sent as `status = label`.
const _statusLabelFilters = <String, Map<String, dynamic>>{
  'Draft': {'docstatus': 0},
  // Every submitted note, whatever its billing or return state.
  'Submitted': {'docstatus': 1},
  'Cancelled': {'docstatus': 2},
  // Every return note: draft, unbilled ("Return") and billed ("Completed").
  'Return': {'is_return': 1},
};

/// Returns the filters to send to the server for the list's [activeFilters].
///
/// Replaces the `status` label with its server filter and leaves every other
/// filter as it is. [activeFilters] is not changed.
Map<String, dynamic> deliveryNoteQueryFilters(
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
