/// List operations for a single recent-search history, newest first.
abstract final class RecentSearches {
  static const limit = 10;
  static final _whitespace = RegExp(r'\s+');

  static String normalize(String query) =>
      query.trim().replaceAll(_whitespace, ' ');

  static List<String> add(
    List<String> current,
    String query, {
    int minLength = 1,
  }) {
    final term = normalize(query);
    if (term.isEmpty || term.length < minLength) return current;
    return [term, ...remove(current, term)].take(limit).toList();
  }

  static List<String> remove(List<String> current, String query) {
    final key = normalize(query).toLowerCase();
    return current.where((term) => term.toLowerCase() != key).toList();
  }

  static List<String> clear() => const [];
}
