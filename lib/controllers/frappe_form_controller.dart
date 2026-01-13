import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../services/frappe_api.dart';

class FrappeFormController extends GetxController {
  final FrappeApiService _api = FrappeApiService();
  final RxMap<String, dynamic> data = <String, dynamic>{}.obs;
  final String doctype;

  FrappeFormController({required this.doctype});

  @override
  void onInit() {
    super.onInit();
    _api.init();
  }

  void initialize(Map<String, dynamic>? initialData) {
    if (initialData != null) {
      data.addAll(initialData);
    }
  }

  void setValue(String fieldname, dynamic value) {
    data[fieldname] = value;
  }

  /// Retrieve a value safely with intelligent type casting
  T? getValue<T>(String fieldname) {
    if (data[fieldname] == null) return null;

    final val = data[fieldname];

    // Auto-convert Int to Double
    if (T == double && val is int) {
      return val.toDouble() as T;
    }
    // Auto-convert Double to Int
    if (T == int && val is double) {
      return val.toInt() as T;
    }
    // Auto-convert Numbers to String (Fixes UI CastErrors)
    if (T == String && (val is int || val is double)) {
      return val.toString() as T;
    }

    return val as T?;
  }

  Future<void> load(String docName) async {
    try {
      data.clear();
      final docData = await _api.getDoc(doctype, docName);
      data.value = docData;
    } catch (e) {
      debugPrint("❌ Error loading $doctype $docName: $e");
      String errorMsg = "Could not load document";
      if (e.toString().contains("403")) errorMsg = "Access Denied. Please login again.";
      if (e.toString().contains("404")) errorMsg = "Document not found.";

      Get.snackbar(
          "Error",
          errorMsg,
          backgroundColor: Get.theme.colorScheme.error.withValues(alpha: 0.1),
          colorText: Get.theme.colorScheme.error,
          duration: const Duration(seconds: 4),
          snackPosition: SnackPosition.BOTTOM
      );
    }
  }

  Future<void> save() async {
    try {
      await _api.saveDoc(doctype, data);
      Get.snackbar("Success", "Saved successfully", snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      debugPrint("❌ Save Error: $e");
      Get.snackbar(
          "Error",
          "Save failed: ${e.toString().replaceAll('Exception:', '')}",
          backgroundColor: Get.theme.colorScheme.error.withValues(alpha: 0.1),
          colorText: Get.theme.colorScheme.error
      );
    }
  }

  Future<List<String>> searchLink(String linkDoctype, String query) {
    return _api.searchLink(linkDoctype, query);
  }
}