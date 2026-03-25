/// Structured representation of a rack asset-code name.
///
/// ## Rack name convention
/// ```
/// KA  - WH   - DXB1 - 101A
/// [0]   [1]    [2]    [3]
///  │     │      │      └─ shelfId     : 3-digit aisle number + shelf letter
///  │     │      └────── locationCode: country / location counter (DXB1, DXB2 …)
///  │     └───────────── locationType: WH = Warehouse, POS = Point-of-Sale …
///  └─────────────────── company     : KA
/// ```
///
/// ## Derived warehouse name
/// ERPNext Warehouse name is derived locally as:
/// ```
/// '${parts[1]}-${parts[2]} - ${parts[0]}'
///   KA-WH-DXB1-101A  →  'WH-DXB1 - KA'
/// ```
///
/// ## Shelf decoding
/// `shelfId` = `101A`
/// - [aisleNumber] = leading integer digits → `101`
/// - [shelfLetter] = trailing alpha characters → `'A'`
/// - [displayLabel] → `'Aisle 101 · Shelf A'`
///
/// ## Null safety
/// Use [RackLocation.tryParse] — returns `null` for any rack name that
/// does not conform to the 4-part pattern.  Callers display the raw rack
/// name when `null` is returned.
class RackLocation {
  /// The raw rack asset-code name, e.g. `'KA-WH-DXB1-101A'`.
  final String rawName;

  /// Company prefix, e.g. `'KA'`.
  final String company;

  /// Location type segment, e.g. `'WH'` or `'POS'`.
  final String locationType;

  /// Location / country counter segment, e.g. `'DXB1'`.
  final String locationCode;

  /// Shelf identifier segment, e.g. `'101A'`.
  final String shelfId;

  /// Aisle (rack) number decoded from [shelfId], e.g. `101`.
  /// `null` if [shelfId] contains no leading digits.
  final int? aisleNumber;

  /// Shelf letter decoded from [shelfId], e.g. `'A'`.
  /// `null` if [shelfId] contains no trailing alpha characters.
  final String? shelfLetter;

  const RackLocation._internal({
    required this.rawName,
    required this.company,
    required this.locationType,
    required this.locationCode,
    required this.shelfId,
    required this.aisleNumber,
    required this.shelfLetter,
  });

  // ── Factory ─────────────────────────────────────────────────────────────────

  /// Parses [rackName] and returns a [RackLocation], or `null` if the name
  /// does not conform to the expected 4-part dash-delimited pattern.
  ///
  /// Safe to call with any string — never throws.
  static RackLocation? tryParse(String rackName) {
    if (rackName.isEmpty) return null;
    final parts = rackName.split('-');
    if (parts.length < 4) return null;

    final company      = parts[0];
    final locationType = parts[1];
    // parts[2] is locationCode; parts[3] is shelfId.
    // If the rack name has more than 4 parts (unlikely but defensive),
    // locationCode is parts[2] and shelfId is everything from parts[3] onward
    // rejoined — preserving the raw value.
    final locationCode = parts[2];
    final shelfId      = parts.sublist(3).join('-');

    if (company.isEmpty || locationType.isEmpty ||
        locationCode.isEmpty || shelfId.isEmpty) {
      return null;
    }

    // ── Decode shelfId → aisleNumber + shelfLetter ────────────────────────
    // Pattern: one or more digits followed by one or more alpha characters.
    // e.g.  '101A' → aisleNumber=101, shelfLetter='A'
    //        '12BC' → aisleNumber=12,  shelfLetter='BC'
    //        '007'  → aisleNumber=7,   shelfLetter=null
    //        'A10'  → aisleNumber=null, shelfLetter=null (non-standard)
    final digitMatch = RegExp(r'^(\d+)([A-Za-z]*)$').firstMatch(shelfId);
    final int?    aisleNumber  = digitMatch != null
        ? int.tryParse(digitMatch.group(1)!)
        : null;
    final String? shelfLetter = (digitMatch != null &&
            digitMatch.group(2) != null &&
            digitMatch.group(2)!.isNotEmpty)
        ? digitMatch.group(2)!.toUpperCase()
        : null;

    return RackLocation._internal(
      rawName:      rackName,
      company:      company,
      locationType: locationType,
      locationCode: locationCode,
      shelfId:      shelfId,
      aisleNumber:  aisleNumber,
      shelfLetter:  shelfLetter,
    );
  }

  // ── Derived properties ───────────────────────────────────────────────────────

  /// ERPNext Warehouse name derived from the rack asset code.
  ///
  /// Formula: `'$locationType-$locationCode - $company'`
  /// Example: `KA-WH-DXB1-101A` → `'WH-DXB1 - KA'`
  String get warehouseName => '$locationType-$locationCode - $company';

  /// Human-readable physical location label for UI display.
  ///
  /// Examples:
  /// - aisleNumber=101, shelfLetter='A'  → `'Aisle 101 · Shelf A'`
  /// - aisleNumber=101, shelfLetter=null → `'Aisle 101'`
  /// - aisleNumber=null, shelfLetter='A' → `'Shelf A'`
  /// - both null                          → shelfId verbatim (safe fallback)
  String get displayLabel {
    if (aisleNumber != null && shelfLetter != null) {
      return 'Aisle $aisleNumber \u00b7 Shelf $shelfLetter';
    }
    if (aisleNumber != null) return 'Aisle $aisleNumber';
    if (shelfLetter != null) return 'Shelf $shelfLetter';
    return shelfId;
  }

  /// Short label suitable for compact UI chips: `'$aisleNumber$shelfLetter'`
  /// or [shelfId] if decoding failed.
  ///
  /// Example: `'101A'`
  String get shortLabel => aisleNumber != null
      ? '$aisleNumber${shelfLetter ?? ""}'
      : shelfId;

  /// `true` when the derived [warehouseName] matches [warehouse]
  /// (case-insensitive).
  bool matchesWarehouse(String warehouse) =>
      warehouseName.toLowerCase() == warehouse.toLowerCase();

  // ── Equality ─────────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RackLocation &&
          runtimeType == other.runtimeType &&
          rawName == other.rawName;

  @override
  int get hashCode => rawName.hashCode;

  @override
  String toString() => 'RackLocation($rawName → $warehouseName, $displayLabel)';
}
