class User {
  final String id;
  final String name;
  final String email;
  final String? designation;
  final String? department;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.designation,
    this.department,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['name'],
      name: json['full_name'],
      email: json['email'],
      designation: json['designation'],
      department: json['department'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': id,
      'full_name': name,
      'email': email,
      'designation': designation,
      'department': department,
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? designation,
    String? department,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      designation: designation ?? this.designation,
      department: department ?? this.department,
    );
  }
}
