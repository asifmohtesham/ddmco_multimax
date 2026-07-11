class ToDo {
  final String name;
  final String status;
  final String description;
  final String modified;
  final String priority;
  final String date;

  /// DocType this ToDo references, e.g. `'Delivery Note'`. Empty when unset.
  final String referenceType;

  /// Document name within [referenceType], e.g. `'DN-00042'`. Empty when unset.
  final String referenceName;

  /// User ID (email) the task is assigned to. Empty when unassigned.
  final String allocatedTo;

  /// User ID (email) that created the ToDo (Frappe's `owner` field).
  final String owner;

  /// User ID (email) that assigned the task, if different from [owner].
  final String assignedBy;

  ToDo({
    required this.name,
    required this.status,
    required this.description,
    required this.modified,
    required this.priority,
    required this.date,
    this.referenceType = '',
    this.referenceName = '',
    this.allocatedTo = '',
    this.owner = '',
    this.assignedBy = '',
  });

  bool get hasReference => referenceType.isNotEmpty && referenceName.isNotEmpty;

  factory ToDo.fromJson(Map<String, dynamic> json) {
    return ToDo(
      name: json['name'] ?? '',
      status: json['status'] ?? 'Open',
      description: json['description'] ?? '',
      modified: json['modified'] ?? '',
      priority: json['priority'] ?? 'Medium',
      date: json['date'] ?? '',
      referenceType: json['reference_type'] ?? '',
      referenceName: json['reference_name'] ?? '',
      allocatedTo: json['allocated_to'] ?? '',
      owner: json['owner'] ?? '',
      assignedBy: json['assigned_by'] ?? '',
    );
  }

  /// Full round-trip serialization (mirrors [fromJson]'s field set) for
  /// caching/persistence and tests. NOT the save-payload contract — that
  /// map is deliberately hand-built in `ToDoFormController.saveDocument`
  /// as an explicit allowlist of user-editable fields, since this includes
  /// server-owned fields (`name`, `owner`) an update PUT must never send.
  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status,
        'description': description,
        'modified': modified,
        'priority': priority,
        'date': date,
        'reference_type': referenceType,
        'reference_name': referenceName,
        'allocated_to': allocatedTo,
        'owner': owner,
        'assigned_by': assignedBy,
      };
}
