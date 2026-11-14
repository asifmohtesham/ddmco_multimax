import 'package:collection/collection.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';

/// One selectable invoice serial in the Packing Slip item sheet dropdown.
class PsSerialOption {
  /// Invoice serial string (DropdownMenuItem value).
  final String serial;

  /// Representative DN row for this serial — the row the sheet re-targets
  /// to when this serial is selected.
  final DeliveryNoteItem dnRow;

  /// DN row qty (the "×N" shown in the dropdown row).
  final double qty;

  /// Remaining unpacked qty for [dnRow]; <= 0 marks the row Full.
  final double remaining;

  const PsSerialOption({
    required this.serial,
    required this.dnRow,
    required this.qty,
    required this.remaining,
  });
}

/// Builds the ordered serial options for the item sheet.
///
/// Filtering: rows must match [code], match [batch] when one was scanned,
/// and carry a real serial (non-null, non-empty, not the '0' sentinel).
/// Dropdown values must be unique, so same-serial rows are deduped: the
/// first row with remaining > 0 wins, else the first row — mirroring
/// [findScannedDnItem]. Sorted ascending by numeric serial (non-numeric
/// serials sort last, matching PackingSlipFormController._allDnSerials).
List<PsSerialOption> buildPsSerialOptions({
  required List<DeliveryNoteItem> items,
  required String code,
  required String? batch,
  required double Function(DeliveryNoteItem) remainingQty,
}) {
  final matches = items.where((item) {
    final serial = item.customInvoiceSerialNumber;
    final codeMatch = item.itemCode == code;
    final batchMatch = (batch == null) || (item.batchNo == batch);
    final serialValid = serial != null && serial.isNotEmpty && serial != '0';
    return codeMatch && batchMatch && serialValid;
  });

  final bySerial =
      groupBy(matches, (DeliveryNoteItem i) => i.customInvoiceSerialNumber!);

  return bySerial.entries.map((entry) {
    final rows = entry.value;
    final row = rows.firstWhereOrNull((r) => remainingQty(r) > 0) ?? rows.first;
    return PsSerialOption(
      serial: entry.key,
      dnRow: row,
      qty: row.qty,
      remaining: remainingQty(row),
    );
  }).toList()
    ..sort((a, b) => (int.tryParse(a.serial) ?? 9999)
        .compareTo(int.tryParse(b.serial) ?? 9999));
}
