class PackingSlip {
  final String name;
  final String deliveryNote;
  final String modified;
  final String creation;
  final int docstatus;
  final String status;

  PackingSlip({
    required this.name,
    required this.deliveryNote,
    required this.modified,
    required this.creation,
    required this.docstatus,
    required this.status,
  });

  factory PackingSlip.fromJson(Map<String, dynamic> json) {
    return PackingSlip(
      name: json['name'] ?? '',
      deliveryNote: json['delivery_note'] ?? '',
      modified: json['modified'] ?? '',
      creation: json['creation'] ?? DateTime.now().toString(),
      docstatus: json['docstatus'] as int? ?? 0,
      // Infer status if not provided, similar to other docs
      status: json['status'] ?? (json['docstatus'] == 1 ? 'Submitted' : (json['docstatus'] == 2 ? 'Cancelled' : 'Draft')),
    );
  }
}
