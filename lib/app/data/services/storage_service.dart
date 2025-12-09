import 'package:multimax/app/data/models/user_model.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class StorageService {
  final GetStorage _box = GetStorage();

  // Keys
  static const String _userKey = 'currentUser';
  static const String _tokenKey = 'apiToken';
  static const String _baseUrlKey = 'baseUrl';

  // --- User Data ---
  Future<void> saveUser(User user) async {
    await _box.write(_userKey, user.toJson());
  }

  User? getUser() {
    final userJson = _box.read<Map<String, dynamic>>(_userKey);
    if (userJson != null) {
      return User.fromJson(userJson);
    }
    return null;
  }

  Future<void> clearUserData() async {
    await _box.remove(_userKey);
    await _box.remove(_tokenKey);
    printInfo(info: "User data cleared from local storage.");
  }

  // --- Token ---
  Future<void> saveToken(String token) async {
    await _box.write(_tokenKey, token);
  }

  String? getToken() {
    return _box.read<String>(_tokenKey);
  }

  // --- Server URL ---
  Future<void> saveBaseUrl(String url) async {
    await _box.write(_baseUrlKey, url);
  }

  String? getBaseUrl() {
    return _box.read<String>(_baseUrlKey);
  }
}