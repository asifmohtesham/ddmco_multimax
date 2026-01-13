import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/item_provider.dart';
import 'package:multimax/controllers/frappe_form_controller.dart';
import 'package:multimax/app/data/models/item_model.dart';

class ItemFormController extends FrappeFormController {
  final ItemProvider _itemProvider = Get.find<ItemProvider>();

  // Specific Observables
  final RxList<WarehouseStock> stockLevels = <WarehouseStock>[].obs;
  final RxList<Map<String, dynamic>> attachments = <Map<String, dynamic>>[].obs;
  final RxBool isLoadingStock = false.obs;

  ItemFormController() : super(doctype: 'Item');

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args != null) {
      if (args is Map && args['itemCode'] != null) {
        load(args['itemCode']);
      } else if (args is String) {
        load(args);
      }
    }
  }

  // ALIAS: Keeps home_controller happy
  void loadItem(String code) {
    load(code);
  }

  @override
  Future<void> load(String docName) async {
    await super.load(docName);
    if (data.isNotEmpty) {
      fetchStockLevels(docName);
    }
  }

  Future<void> fetchStockLevels(String itemCode) async {
    isLoadingStock.value = true;
    try {
      final response = await _itemProvider.getStockLevels(itemCode);
      if (response.statusCode == 200 && response.data['message']?['result'] != null) {
        final List<dynamic> result = response.data['message']['result'];
        stockLevels.value = result
            .whereType<Map<String, dynamic>>()
            .map((json) => WarehouseStock.fromJson(json))
            .toList();
      }
    } catch (e) {
      print("Stock fetch error: $e");
    } finally {
      isLoadingStock.value = false;
    }
  }

  // Getters for specific UI logic (optional but useful)
  String get itemCode => getValue('item_code') ?? '';
  String get itemName => getValue('item_name') ?? '';
  String? get image => getValue('image');
}