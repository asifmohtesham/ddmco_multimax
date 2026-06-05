class CustomerEntry {
  final String name;
  final String customerName;
  final String customerGroup;
  final String territory;

  const CustomerEntry({
    required this.name,
    required this.customerName,
    required this.customerGroup,
    required this.territory,
  });

  factory CustomerEntry.fromJson(Map<String, dynamic> json) {
    return CustomerEntry(
      name: json['name']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      customerGroup: json['customer_group']?.toString() ?? '',
      territory: json['territory']?.toString() ?? '',
    );
  }
}
