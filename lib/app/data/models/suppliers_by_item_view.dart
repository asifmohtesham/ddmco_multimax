enum SuppliersByItemGroup { template, supplier }

enum SuppliersByItemSortField { stock, supplierCount, lastPurchase }

enum SuppliersByItemSortDirection { asc, desc }

class SuppliersByItemView {
  const SuppliersByItemView({
    this.group = SuppliersByItemGroup.template,
    this.sortField = SuppliersByItemSortField.stock,
    this.sortDirection = SuppliersByItemSortDirection.desc,
  });

  factory SuppliersByItemView.fromJson(Object? json) {
    if (json is! Map) return const SuppliersByItemView();
    const defaults = SuppliersByItemView();
    return SuppliersByItemView(
      group: _readEnum(
        SuppliersByItemGroup.values,
        json['group'],
        defaults.group,
      ),
      sortField: _readEnum(
        SuppliersByItemSortField.values,
        json['sortField'],
        defaults.sortField,
      ),
      sortDirection: _readEnum(
        SuppliersByItemSortDirection.values,
        json['sortDirection'],
        defaults.sortDirection,
      ),
    );
  }

  final SuppliersByItemGroup group;
  final SuppliersByItemSortField sortField;
  final SuppliersByItemSortDirection sortDirection;

  static T _readEnum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  Map<String, String> toJson() => {
    'group': group.name,
    'sortField': sortField.name,
    'sortDirection': sortDirection.name,
  };

  SuppliersByItemView copyWith({
    SuppliersByItemGroup? group,
    SuppliersByItemSortField? sortField,
    SuppliersByItemSortDirection? sortDirection,
  }) => SuppliersByItemView(
    group: group ?? this.group,
    sortField: sortField ?? this.sortField,
    sortDirection: sortDirection ?? this.sortDirection,
  );

  @override
  bool operator ==(Object other) =>
      other is SuppliersByItemView &&
      other.group == group &&
      other.sortField == sortField &&
      other.sortDirection == sortDirection;

  @override
  int get hashCode => Object.hash(group, sortField, sortDirection);
}
