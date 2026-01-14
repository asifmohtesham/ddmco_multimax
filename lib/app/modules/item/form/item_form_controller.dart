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

    // Safely retrieve arguments
    final dynamic args = Get.arguments;

    // 1. Determine Mode
    bool isNew = false;
    String? loadId;

    if (args == null) {
      isNew = true;
    } else if (args is Map) {
      if (args['mode'] == 'new') {
        isNew = true;
      } else if (args['itemCode'] != null) {
        loadId = args['itemCode'].toString();
      }
    } else if (args is String) {
      loadId = args;
    }

    // 2. Execute Action
    if (isNew) {
      _initNewItem();
    } else if (loadId != null && loadId.isNotEmpty) {
      load(loadId);
    } else {
      // Fallback if args are weird but not null
      _initNewItem();
    }
  }

  void _initNewItem() {
    // Populate data with defaults so the UI renders
    print("Initializing New Item...");
    initialize({
      'docstatus': 0,
      'item_code': '',
      'item_name': '',
      'description': '',
      'item_group': 'All Item Groups',
      'is_stock_item': 1,
      'has_batch_no': 0,
      'has_serial_no': 0,
      '__islocal': 1,
    });
  }

  // ALIAS: Keeps home_controller happy
  void loadItem(String code) {
    load(code);
  }

  @override
  Future<void> load(String docName) async {
    await super.load(docName);
    // Only fetch stock if we successfully loaded an existing item
    if (data.isNotEmpty) {
      fetchStockLevels(docName);
    }
  }

  Future<void> fetchStockLevels(String itemCode) async {
    isLoadingStock.value = true;
    try {
      final response = await _itemProvider.getStockLevels(itemCode);
      if (response.statusCode == 200 &&
          response.data['message']?['result'] != null) {
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

  // Getters for specific UI logic
  String get itemCode => getValue('item_code') ?? '';

  String get itemName => getValue('item_name') ?? '';

  String? get image => getValue('image');
}
