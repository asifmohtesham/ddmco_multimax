enum PosDeliveryAction {
  outForDelivery('Out for Delivery'),
  deliveryReturn('Delivery Return'),
  delivered('Delivered'),
  revertToPending('Revert to Pending');

  const PosDeliveryAction(this.label);

  final String label;

  bool get requiresReason => this == deliveryReturn;

  /// Delivery actions record the outsourced driver. Revert to Pending (Stock
  /// Manager only) just reopens preparation, so it takes no driver.
  bool get requiresDriver => this != revertToPending;

  static PosDeliveryAction? fromLabel(Object? label) {
    for (final action in values) {
      if (action.label == label) return action;
    }
    return null;
  }
}

enum PosDeliveryReason {
  late('Late', 'Delivery delayed'),
  rejected('Rejected', 'Rejected by customer'),
  other('Other', 'Other reason');

  const PosDeliveryReason(this.label, this.description);

  final String label;
  final String description;

  static PosDeliveryReason? fromLabel(Object? label) {
    for (final reason in values) {
      if (reason.label == label) return reason;
    }
    return null;
  }
}

class PosDeliveryDriver {
  const PosDeliveryDriver({required this.name, required this.fullName});

  final String name;
  final String fullName;
}

class PosDeliveryDriverOptions {
  const PosDeliveryDriverOptions({
    required this.drivers,
    required this.defaultDriver,
  });

  final List<PosDeliveryDriver> drivers;
  final String? defaultDriver;
}

class PosDeliverySelection {
  const PosDeliverySelection({this.driver, this.reason});

  final String? driver;
  final PosDeliveryReason? reason;
}
