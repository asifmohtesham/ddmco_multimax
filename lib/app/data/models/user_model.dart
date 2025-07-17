class User {
  final String id;
  final String name;
  final String email;
  final String? token; // Example: if your API returns a token

  User({
    required this.id,
    required this.name,
    required this.email,
    this.token,
  });

  // Factory constructor to create a User from JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      token: json['token'] as String?,
    );
  }

  // Method to convert User instance to JSON (useful for storing locally)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'token': token,
    };
  }
}