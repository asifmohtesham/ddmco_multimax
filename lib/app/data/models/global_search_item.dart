/// A standardised model representing a search result item.
/// This decouples the UI from the raw API response structure.
class GlobalSearchItem {
  final String id; // The unique identifier (name)
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final Map<String, dynamic> rawData; // valid payload for debugging or advanced use

  GlobalSearchItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.rawData,
  });
}