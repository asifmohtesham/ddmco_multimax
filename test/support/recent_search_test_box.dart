class RecentSearchTestBox {
  final data = <String, Object>{};
  int writes = 0;

  T? read<T>(String key) => data[key] as T?;

  Future<void> write(String key, Object value) async {
    writes++;
    data[key] = value;
  }

  Future<void> remove(String key) async {
    data.remove(key);
  }
}
