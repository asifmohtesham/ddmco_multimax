import 'package:ddmco_multimax/app/data/models/user_model.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:ddmco_multimax/app/data/models/user_model.dart'; // Update path

class StorageService {
  final GetStorage _box = GetStorage(); // Default box or a named one

  // Keys for storage
  static const String _userKey = 'currentUser';
  static const String _tokenKey = 'apiToken'; // If you store tokens separately

  // Save User
  Future<void> saveUser(User user) async {
    await _box.write(_userKey, user.toJson());
  }

  // Get User
  User? getUser() {
    final userJson = _box.read<Map<String, dynamic>>(_userKey);
    if (userJson != null) {
      return User.fromJson(userJson);
    }
    return null;
  }

  // --- NEW METHOD ---
  Future<void> clearUserData() async {
    await _box.remove(_userKey);
    await _box.remove(_tokenKey); // If you store a token separately
    // Clear any other user-specific data you store
    printInfo(info: "User data cleared from local storage.");
  }

  // Example for token storage (if not using cookies exclusively)
  Future<void> saveToken(String token) async {
    await _box.write(_tokenKey, token);
  }

  String? getToken() {
    return _box.read<String>(_tokenKey);
  }
}
