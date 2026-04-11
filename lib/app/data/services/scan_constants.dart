/// Centralised constants for barcode scanning logic.
///
/// All magic strings, field names, and prefix literals used by [ScanService]
/// live here so that a single source change propagates everywhere.
class ScanConstants {
  ScanConstants._();

  // ── Shipment prefix variants ──────────────────────────────────────────────
  /// Year-qualified shipment prefix, e.g. barcodes printed in 2024.
  /// Update this each year or replace with a dynamic prefix when the
  /// barcode generation scheme is formalised.
  static const String shipmentPrefix24 = 'SHIPMENT-24-';

  /// Generic (year-agnostic) shipment prefix.
  static const String shipmentPrefix = 'SHIPMENT-';

  // ── ERPNext DocType names ─────────────────────────────────────────────────
  static const String doctypeItem = 'Item';

  // ── ERPNext field names ───────────────────────────────────────────────────
  static const String fieldName = 'name';
  static const String fieldVariantOf = 'variant_of';

  // ── Regex patterns ────────────────────────────────────────────────────────
  /// Matches codes that are safe alphanumeric batch suffix candidates.
  static final RegExp alphanumericSuffix =
      RegExp(r'^[a-zA-Z0-9]{3,}$');

  /// Matches strings that consist entirely of ASCII digits.
  static final RegExp digitsOnly = RegExp(r'^\d+$');
}
