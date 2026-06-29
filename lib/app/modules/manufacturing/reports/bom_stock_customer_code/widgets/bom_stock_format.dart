/// Safely coerces a dynamic report value to a num, or null if it cannot be one.
/// ERPNext emits Float/Int columns as JSON numbers, but this guards against a
/// stray String so the parse/render paths never throw.
num? toNum(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '');

/// Formats a report quantity: integers without decimals, otherwise 2 dp.
String formatQty(num? v) {
  if (v == null) return '—';
  final d = v.toDouble();
  return d == d.roundToDouble()
      ? d.toStringAsFixed(0)
      : d.toStringAsFixed(2);
}
