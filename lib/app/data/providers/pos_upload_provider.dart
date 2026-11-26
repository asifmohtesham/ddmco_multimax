import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pos_upload_delivery.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class PosUploadProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<Response> getPosUploads({
    int limit = 50,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    List<List<dynamic>>? orFilterTuples,
    String orderBy = 'modified desc',
  }) async {
    // POS Upload specific logic to exclude cancelled/deleted if needed
    if (filters != null && filters.containsKey('docstatus')) {
      filters.remove('docstatus');
    }

    return _apiProvider.getDocumentList(
      'POS Upload',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orFilterTuples: orFilterTuples,
      orderBy: orderBy,
      // Added 'total_qty'
      fields: ['name', 'customer', 'date', 'modified', 'status', 'total_qty'],
    );
  }

  Future<Response> getPosUpload(String name) async {
    return _apiProvider.getPosUpload(name);
  }

  Future<List<PosDeliveryAction>> getDeliveryActions(String name) async {
    final Object? transitions;
    try {
      final response = await _apiProvider.callMethod(
        'frappe.model.workflow.get_transitions',
        params: {
          'doc': jsonEncode({'doctype': 'POS Upload', 'name': name}),
        },
      );
      transitions = _requireSuccess(response)['message'];
    } on DioException catch (error) {
      if (_isMissingWorkflow(error.response)) return [];
      rethrow;
    }
    if (transitions is! List) {
      throw const FormatException('Invalid workflow transitions');
    }
    final actions = <PosDeliveryAction>{};
    for (final transition in transitions) {
      if (transition is! Map) continue;
      final action = PosDeliveryAction.fromLabel(transition['action']);
      if (action != null) actions.add(action);
    }
    return actions.toList();
  }

  // Frappe loads "Workflow None" when this DocType has no active workflow.
  bool _isMissingWorkflow(Response? response) {
    if (response?.statusCode != 404) return false;
    final data = response?.data;
    if (data is! Map || data['exc_type'] != 'DoesNotExistError') return false;
    final rawMessages = data['_server_messages'];
    if (rawMessages is! String) return false;
    try {
      final messages = jsonDecode(rawMessages);
      if (messages is! List || messages.length != 1) return false;
      final rawMessage = messages.single;
      if (rawMessage is! String) return false;
      final message = jsonDecode(rawMessage);
      return message is Map && message['message'] == 'Workflow None not found';
    } on FormatException {
      return false;
    }
  }

  Future<PosDeliveryDriverOptions> getDeliveryDrivers(
    String name,
    PosDeliveryAction action,
  ) async {
    final response = await _apiProvider.callMethod(
      'pos_upload_delivery_drivers',
      params: {'name': name, 'action': action.label},
    );
    final message = _requireSuccess(response)['message'];
    if (message is! Map || message['drivers'] is! List) {
      throw const FormatException('Invalid delivery driver options');
    }
    final drivers = <String, PosDeliveryDriver>{};
    for (final row in message['drivers'] as List) {
      if (row is! Map) continue;
      final name = row['name'];
      if (name is! String || name.isEmpty) continue;
      final fullName = row['full_name']?.toString().trim() ?? '';
      drivers[name] = PosDeliveryDriver(
        name: name,
        fullName: fullName.isEmpty ? name : fullName,
      );
    }
    final defaultDriver = message['default_driver'];
    return PosDeliveryDriverOptions(
      drivers: drivers.values.toList(),
      defaultDriver: drivers.containsKey(defaultDriver)
          ? defaultDriver as String
          : null,
    );
  }

  Future<PosUpload> applyDeliveryAction(
    PosUpload upload,
    PosDeliveryAction action,
    PosDeliverySelection selection,
  ) async {
    final reason = selection.reason;
    if (action.requiresReason && reason == null) {
      throw ArgumentError('Delivery Return requires a reason');
    }
    final driver = selection.driver;
    if (action.requiresDriver && (driver == null || driver.isEmpty)) {
      throw ArgumentError('${action.label} requires a driver');
    }
    final response = await _apiProvider.callMethodPost(
      'frappe.model.workflow.apply_workflow',
      jsonBody: true,
      params: {
        'action': action.label,
        'doc': {
          'doctype': 'POS Upload',
          'name': upload.name,
          'modified': upload.modified,
          if (action.requiresDriver) 'pos_delivery_driver': driver,
          if (action.requiresReason) 'pos_delivery_reason': reason!.label,
        },
      },
    );
    final doc = _requireSuccess(response)['message'];
    if (doc is! Map<String, dynamic> ||
        doc['name'] != upload.name ||
        doc['modified'] is! String ||
        (doc['modified'] as String).isEmpty) {
      throw const FormatException('Invalid saved POS Upload');
    }
    return PosUpload.fromJson(doc);
  }

  Future<Map<String, dynamic>?> getDeliveryDocinfo(String name) async {
    final response = await _apiProvider.callMethod(
      'frappe.desk.form.load.get_docinfo',
      params: {'doctype': 'POS Upload', 'name': name},
    );
    final docinfo = _requireSuccess(response)['docinfo'];
    return docinfo is Map<String, dynamic> ? docinfo : null;
  }

  Map _requireSuccess(Response response) {
    if (response.statusCode != 200) {
      throw DioException.badResponse(
        statusCode: response.statusCode ?? 0,
        requestOptions: response.requestOptions,
        response: response,
      );
    }
    final data = response.data;
    if (data is! Map) throw const FormatException('Invalid Frappe response');
    return data;
  }

  Future<Response> updatePosUpload(String name, Map<String, dynamic> data) async {
    return _apiProvider.updateDocument('POS Upload', name, data);
  }

  /// Whether the current session user may write (update) the specific
  /// POS Upload [name]. Fail-closed: returns `false` on any network or
  /// permission error.
  Future<bool> canWrite(String name) async {
    try {
      final res =
          await _apiProvider.hasDocPermission('POS Upload', name, 'write');
      return ApiProvider.parseHasDocPermissionResponse(res.data);
    } catch (_) {
      return false;
    }
  }

  /// Whether a user holding [userRoles] may write the `status` field, which
  /// is permlevel-gated on the server (doc-level write alone is not enough —
  /// Frappe silently discards higher-permlevel changes from users without a
  /// write rule at that level). Complements [canWrite]; both must pass
  /// before the Status control is enabled. Fail-closed on any error.
  Future<bool> canWriteStatusField(Set<String> userRoles) async {
    try {
      final meta = await _apiProvider.getDocTypeMeta('POS Upload');
      return ApiProvider.fieldWriteGranted(
          meta.data, 'POS Upload', 'status', userRoles);
    } catch (_) {
      return false;
    }
  }
}