enum StockEntrySource {
  manual,
  workOrder,       // Material Transfer for Manufacture (has items in args)
  manufacture,     // Stock Entry: Manufacture (no items in args — fetched after save)
  materialRequest,
  posUpload,
}

class MrItemRow {
  final String itemCode;
  final double requestedQty;
  final double scannedQty;
  final String materialRequest;
  final String materialRequestItem;

  const MrItemRow({
    required this.itemCode,
    required this.requestedQty,
    required this.scannedQty,
    required this.materialRequest,
    required this.materialRequestItem,
  });

  bool get isCompleted => scannedQty >= requestedQty;
  bool get isPending   => scannedQty < requestedQty;
}