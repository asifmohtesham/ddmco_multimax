/// One Stock Ageing row for an item: a single row for the whole of Finished
/// Goods, or one per warehouse when the report gives one per warehouse.
class ItemAgeing {
  const ItemAgeing({
    this.warehouse,
    required this.availableQty,
    required this.averageAge,
    required this.earliest,
    required this.latest,
    required this.buckets,
  });

  /// Set only when the run gives one row per warehouse.
  final String? warehouse;
  final double availableQty;
  final double averageAge;

  /// Age in days of the oldest and the newest batch.
  final int earliest;
  final int latest;

  /// Quantity per age bucket, labelled as the report titles it ("0 - 90").
  final List<({String label, double qty})> buckets;
}

enum AgeingStatus { loading, ready, missing, failed, denied }

/// Where an item's Stock Ageing lookup stands, with its rows once ready.
class AgeingState {
  const AgeingState(this.status, [this.rows = const []]);

  final AgeingStatus status;
  final List<ItemAgeing> rows;
}
