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

  // ── POS Upload document names ─────────────────────────────────────────────
  /// A POS Upload document name: `<PREFIX>-<YEAR>-<SERIAL>`, e.g.
  /// `ML-2026-02011` or `KA-2025-61960`. PREFIX is one of ML/KA (Delivery
  /// Note family) or MX/KX (Stock Entry family); YEAR is 4 digits; SERIAL is
  /// 4–6 digits (5 in practice — the extra tolerance future-proofs against
  /// naming-series growth).
  ///
  /// Deliberately anchored and prefix-restricted so it never collides with the
  /// other hyphenated codes the scanner sees: rack asset-codes
  /// (`KA-WH-DXB1-101A` — non-numeric second segment), batch ids
  /// (`{EAN8}-{suffix}` — 8-digit first segment), or ERPNext DN/SE names
  /// (`MAT-DN-2026-00042` — 3-letter prefix).
  static final RegExp posUploadDocName =
      RegExp(r'^(?:ML|KA|MX|KX)-\d{4}-\d{4,6}$', caseSensitive: false);

  /// Whether [code] (trimmed) is a POS Upload document name. See
  /// [posUploadDocName].
  static bool isPosUploadDocName(String code) =>
      posUploadDocName.hasMatch(code.trim());

  /// Whether [code] is a Stock-Entry-family POS Upload (MX/KX prefix). These
  /// link to a Stock Entry and have no Packing Slip, so a Dashboard scan of one
  /// opens the Stock Entry directly rather than offering a DN/PS choice. ML/KA
  /// are Delivery-Note family. Assumes [isPosUploadDocName] is already true.
  static bool isStockEntryFamilyUpload(String code) {
    final prefix = code.trim().toUpperCase();
    return prefix.startsWith('MX') || prefix.startsWith('KX');
  }
}
