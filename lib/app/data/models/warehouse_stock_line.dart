/// One Stock Balance line for the Dashboard-search warehouse section:
/// an item's balance quantity in the default warehouse.
class WarehouseStockLine {
  final String itemCode;
  final String itemName;
  final double balanceQty;
  final String uom;

  const WarehouseStockLine({
    required this.itemCode,
    required this.itemName,
    required this.balanceQty,
    required this.uom,
  });
}
