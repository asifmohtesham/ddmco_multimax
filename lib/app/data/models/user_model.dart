import 'package:flutter/foundation.dart';

class User {
  final String id;
  final String name;
  final String email;
  final String? image;
  final String? designation;
  final String? department;
  final String? mobileNo;
  final String? employeeId;
  final List<String> roles;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.image,
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

    // Frappe exposes the avatar as 'user_image'; fall back to 'image'.
    final rawImage = json['user_image'] ?? json['image'];
    final imageUrl = (rawImage is String && rawImage.isNotEmpty)
        ? rawImage
        : null;

    return User(
      id:          json['name'],
      name:        json['full_name'] ?? json['name'],
      email:       json['email'] ?? json['name'],
      image:       imageUrl,
      designation: json['designation'],
      department:  json['department'],
      mobileNo:    json['mobile_no'],
      employeeId:  json['employee_id'],
      roles:       rolesList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name':        id,
      'full_name':   name,
      'email':       email,
      'user_image':  image,
      'designation': designation,
      'department':  department,
      'mobile_no':   mobileNo,
      'employee_id': employeeId,
      'roles':       roles.map((r) => {'role': r}).toList(),
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? image,
    String? designation,
    String? department,
    String? mobileNo,
    String? employeeId,
    List<String>? roles,
  }) {
    return User(
      id:          id          ?? this.id,
      name:        name        ?? this.name,
      email:       email       ?? this.email,
      image:       image       ?? this.image,
      designation: designation ?? this.designation,
      department:  department  ?? this.department,
      mobileNo:    mobileNo    ?? this.mobileNo,
      employeeId:  employeeId  ?? this.employeeId,
      roles:       roles       ?? this.roles,
    );
  }

  bool hasRole(String role) => roles.contains(role);
}
