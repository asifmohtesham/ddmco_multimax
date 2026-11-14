import 'package:multimax/app/data/models/delivery_note_model.dart';

/// Item-group leaf names whose quantities must match per Invoice Serial Number.
/// Exact, case-sensitive, plural ERPNext group names.
const String kStrapItemGroup = 'Straps';
const String kBuckleItemGroup = 'Buckles';

/// Quantities within [1e-9] of each other are treated as equal (qty is double).
const double _kQtyEpsilon = 1e-9;

/// True when [itemGroup] participates in the strap/buckle pairing rule.
bool isPairedItemGroup(String? itemGroup) =>
    itemGroup == kStrapItemGroup || itemGroup == kBuckleItemGroup;

/// Delivered Strap and Buckle totals for [serial] across all [items].
({double strap, double buckle}) strapBuckleQtyFor(
    List<DeliveryNoteItem> items, String serial) {
  double strap = 0.0;
  double buckle = 0.0;
  for (final item in items) {
    if (item.customInvoiceSerialNumber != serial) continue;
    if (item.itemGroup == kStrapItemGroup) {
      strap += item.qty;
    } else if (item.itemGroup == kBuckleItemGroup) {
      buckle += item.qty;
    }
  }
  return (strap: strap, buckle: buckle);
}

/// True when [serial]'s delivered Strap/Buckle quantities are mismatched.
///
/// Balanced (false) when either group is absent (the "or 0" rule) or the two
/// group totals are equal within [_kQtyEpsilon].
bool isSerialStrapBuckleUnbalanced(
    List<DeliveryNoteItem> items, String serial) {
  final q = strapBuckleQtyFor(items, serial);
  if (q.strap <= 0 || q.buckle <= 0) return false;
  return (q.strap - q.buckle).abs() > _kQtyEpsilon;
}

/// True when packing an [itemGroup] item on [serial] must be blocked: the item
/// is paired (Straps/Buckles) AND [serial] is strap/buckle-unbalanced in [items].
///
/// This is the single authoritative predicate every Packing Slip entry point
/// consults (serial dropdown, scan, tap-to-add, and the add commit), so all
/// paths agree on what is blocked. A non-paired group or a null / empty /
/// sentinel ('0') serial is never blocked.
bool isPackBlockedByBalance(
    List<DeliveryNoteItem> items, String? itemGroup, String? serial) {
  if (!isPairedItemGroup(itemGroup)) return false;
  if (serial == null || serial.isEmpty || serial == '0') return false;
  return isSerialStrapBuckleUnbalanced(items, serial);
}
