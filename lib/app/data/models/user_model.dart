class User {
  final String id;
  final String name;
  final String email;
  final String? designation;
  final String? department;
  final String? mobileNo;
  final String? employeeId; // Added: Links to Employee Document
  final List<String> roles;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.designation,
    this.department,
    this.mobileNo,
    this.employeeId,
    required this.roles,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    var rolesList = <String>[];
    if (json['roles'] != null) {
      rolesList = (json['roles'] as List)
          .map((r) => r['role'] as String)
          .toList();
    }

    return User(
      id: json['name'],
      name: json['full_name'] ?? json['name'],
      email: json['email'] ?? json['name'],
      designation: json['designation'],
      department: json['department'],
      mobileNo: json['mobile_no'],
      employeeId: json['employee_id'], // Load from storage/custom logic
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
      'mobile_no': mobileNo,
      'employee_id': employeeId, // Persist to storage
      'roles': roles.map((r) => {'role': r}).toList(),
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? designation,
    String? department,
    String? mobileNo,
    String? employeeId,
    List<String>? roles,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      mobileNo: mobileNo ?? this.mobileNo,
      employeeId: employeeId ?? this.employeeId,
      roles: roles ?? this.roles,
    );
  }

  bool hasRole(String role) => roles.contains(role);
}