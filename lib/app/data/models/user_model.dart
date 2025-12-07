class User {
  final String id;
  final String name;
  final String email;
  final String? designation;
  final String? department;
  final List<String> roles; // Added roles list

  User({
    required this.id,
    required this.name,
    required this.email,
    this.designation,
    this.department,
    required this.roles,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Parse roles from Frappe child table format: [{'role': 'System Manager'}, ...]
    var rolesList = <String>[];
    if (json['roles'] != null) {
      rolesList = (json['roles'] as List)
          .map((r) => r['role'] as String)
          .toList();
    }

    return User(
      id: json['name'],
      name: json['full_name'],
      email: json['email'],
      designation: json['designation'],
      department: json['department'],
      roles: rolesList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': id,
      'full_name': name,
      'email': email,
      'designation': designation,
      'department': department,
      'roles': roles.map((r) => {'role': r}).toList(),
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? designation,
    String? department,
    List<String>? roles,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      roles: roles ?? this.roles,
    );
  }

  // Helper to check for specific role
  bool hasRole(String role) => roles.contains(role);
}