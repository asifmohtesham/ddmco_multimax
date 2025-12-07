class User {
  final String id;
  final String name;
  final String email;
  final String? designation;
  final String? department;
  final String? mobileNo; // Added mobile number
  final List<String> roles;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.designation,
    this.department,
    this.mobileNo,
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
      name: json['full_name'],
      email: json['email'],
      designation: json['designation'],
      department: json['department'],
      mobileNo: json['mobile_no'], // Parse mobile_no
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
    List<String>? roles,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      designation: designation ?? this.designation,
      department: department ?? this.department,
      mobileNo: mobileNo ?? this.mobileNo,
      roles: roles ?? this.roles,
    );
  }

  bool hasRole(String role) => roles.contains(role);
}