/// Formats a report quantity: integers without decimals, otherwise 2 dp.
String formatQty(num? v) {
  if (v == null) return '—';
  final d = v.toDouble();
  return d == d.roundToDouble()
      ? d.toStringAsFixed(0)
      : d.toStringAsFixed(2);
}
