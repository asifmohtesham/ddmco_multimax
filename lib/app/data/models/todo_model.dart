class ToDo {
  final String name;
  final String status;
  final String description;
  final String modified;
  final String priority;
  final String date;

  ToDo({
    required this.name,
    required this.status,
    required this.description,
    required this.modified,
    required this.priority,
    required this.date,
  });

  factory ToDo.fromJson(Map<String, dynamic> json) {
    return ToDo(
      name: json['name'] ?? '',
      status: json['status'] ?? 'Open',
      description: json['description'] ?? '',
      modified: json['modified'] ?? '',
      priority: json['priority'] ?? 'Medium',
      date: json['date'] ?? '',
    );
  }
}
