// app/data/providers/packing_slip_provider.dart
import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/api_provider.dart';

class PackingSlipProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  static const List<String> _listFields = [
    'name',
    'delivery_note',
    'modified',
    'creation',
    'docstatus',
    'status',
    'custom_po_no',
    'from_case_no',
    'to_case_no',
    'owner',
  ];

  Future<Response> getPackingSlips({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'creation desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Packing Slip',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      fields: _listFields,
    );
  }

  Future<Response> getPackingSlip(String name) async {
    return _apiProvider.getDocument('Packing Slip', name);
  }

  // ── Search helpers for filter pickers ──────────────────────────────────────

  /// Delivery Notes for the DN picker (draft + submitted only).
  Future<Response> searchDeliveryNotes(String query) async {
    return _apiProvider.getDocumentList(
      'Delivery Note',
      filters: {
        'name': ['like', '%$query%'],
        'docstatus': ['<', 2],
      },
      fields: ['name', 'customer', 'po_no'],
      limit: 20,
      orderBy: 'modified desc',
    );
  }

  /// Unique PO numbers recorded on existing Packing Slips.
  Future<Response> searchPONumbers(String query) async {
    return _apiProvider.getDocumentList(
      'Packing Slip',
      filters: {
        'custom_po_no': ['like', '%$query%'],
      },
      fields: ['custom_po_no'],
      limit: 30,
      orderBy: 'custom_po_no asc',
    );
  }
}
