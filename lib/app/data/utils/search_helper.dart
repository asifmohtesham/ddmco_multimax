class SearchHelper {
  /// Filters a list of items based on a multi-token query against multiple fields.
  ///
  /// [items]: The list of objects to filter.
  /// [query]: The search string (e.g., "wallet 895").
  /// [searchables]: A function that returns a list of strings to search within for a given item.
  ///
  /// Logic:
  /// 1. Splits [query] into tokens (e.g., ["wallet", "895"]).
  /// 2. For an item to match, *every* token must be found in *at least one* of the [searchables].
  ///    This allows "895 wallet" to match an item with name "Wallet" and code "895".
  static List<T> search<T>(
      List<T> items,
      String query,
      List<String?> Function(T) searchables,
      ) {
    if (query.trim().isEmpty) return items;

    final tokens = query.toLowerCase().trim().split(RegExp(r'\s+'));

    return items.where((item) {
      // Get all searchable values for this item, lowercased and non-null
      final values = searchables(item)
          .where((s) => s != null)
          .map((s) => s!.toLowerCase())
          .toList();

      // Check if ALL tokens have a match in ANY of the values
      return tokens.every((token) {
        return values.any((value) => value.contains(token));
      });
    }).toList();
  }
}