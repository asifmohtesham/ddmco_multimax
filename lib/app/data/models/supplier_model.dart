class SupplierEntry {
  final String name;
  final String supplierName;
  final String supplierGroup;

  const SupplierEntry({
    required this.name,
    required this.supplierName,
    required this.supplierGroup,
  });

  factory SupplierEntry.fromJson(Map<String, dynamic> json) {
    return SupplierEntry(
      name: json['name']?.toString() ?? '',
      supplierName: json['supplier_name']?.toString() ?? '',
      supplierGroup: json['supplier_group']?.toString() ?? '',
    );
  }
}
