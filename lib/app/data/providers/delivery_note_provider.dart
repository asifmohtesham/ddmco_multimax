import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

enum PosUploadDeliveryNoteStatus {
  submitted,
  draft,
  missing,
  ambiguous,
  unavailable,
}

class PosUploadDeliveryNoteLink {
  const PosUploadDeliveryNoteLink._(this.status, [this.name]);
  const PosUploadDeliveryNoteLink.unavailable()
    : this._(PosUploadDeliveryNoteStatus.unavailable);

  final PosUploadDeliveryNoteStatus status;
  final String? name;

  bool get isDraft => status == PosUploadDeliveryNoteStatus.draft;

  String? get notice => switch (status) {
    PosUploadDeliveryNoteStatus.submitted ||
    PosUploadDeliveryNoteStatus.draft => null,
    PosUploadDeliveryNoteStatus.missing => 'No submitted Delivery Note',
    PosUploadDeliveryNoteStatus.ambiguous =>
      'Multiple submitted Delivery Notes. Ask Stock Manager to reconcile them.',
    PosUploadDeliveryNoteStatus.unavailable => 'Unable to read Delivery Notes',
  };
}

class DeliveryNoteProvider {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  Future<PosUploadDeliveryNoteLink> resolvePosUploadDeliveryNote(
    PosUpload upload,
  ) async {
    try {
      final submitted = await _getOutboundNotesForPosUpload(
        upload.name,
        docstatus: 1,
        limit: 2,
      );
      if (submitted.length > 1) {
        return const PosUploadDeliveryNoteLink._(
          PosUploadDeliveryNoteStatus.ambiguous,
        );
      }
      if (submitted.isNotEmpty) {
        return PosUploadDeliveryNoteLink._(
          PosUploadDeliveryNoteStatus.submitted,
          submitted.single,
        );
      }
      if (upload.isInPreparation) {
        final drafts = await _getOutboundNotesForPosUpload(
          upload.name,
          docstatus: 0,
          limit: 1,
        );
        if (drafts.isNotEmpty) {
          return PosUploadDeliveryNoteLink._(
            PosUploadDeliveryNoteStatus.draft,
            drafts.first,
          );
        }
      }
      return const PosUploadDeliveryNoteLink._(
        PosUploadDeliveryNoteStatus.missing,
      );
    } catch (_) {
      return const PosUploadDeliveryNoteLink.unavailable();
    }
  }

  Future<List<String>> _getOutboundNotesForPosUpload(
    String name, {
    required int docstatus,
    required int limit,
  }) async {
    final response = await _apiProvider.getDocumentList(
      'Delivery Note',
      fields: const ['name'],
      filters: {'po_no': name, 'docstatus': docstatus, 'is_return': 0},
      limit: limit,
    );
    final data = response.data;
    if (response.statusCode != 200 || data is! Map || data['data'] is! List) {
      throw const FormatException('Unable to read Delivery Notes');
    }
    return (data['data'] as List).map((row) {
      final name = row is Map ? row['name'] : null;
      if (name is! String || name.isEmpty) {
        throw const FormatException('Missing Delivery Note name');
      }
      return name;
    }).toList();
  }

  Future<Response> getDeliveryNotes({
    int limit = 20,
    int limitStart = 0,
    Map<String, dynamic>? filters,
    String orderBy = 'modified desc',
  }) async {
    return _apiProvider.getDocumentList(
      'Delivery Note',
      limit: limit,
      limitStart: limitStart,
      filters: filters,
      orderBy: orderBy,
      fields: [
        'name',
        'customer',
        'grand_total',
        'posting_date',
        'modified',
        'modified_by',
        'owner',
        'status',
        'currency',
        'po_no',
        'total_qty',
        'creation',
        'docstatus',
        'set_warehouse',
      ],
    );
  }

  Future<Response> getDeliveryNote(String name) async {
    return _apiProvider.getDeliveryNote(name);
  }

  Future<Response> getPosUploads(
      {int limit = 100,
      int limitStart = 0,
      Map<String, dynamic>? filters}) async {
    return _apiProvider.getPosUploads(
        limit: limit, limitStart: limitStart, filters: filters);
  }

  Future<Response> getPosUpload(String name) async {
    return _apiProvider.getPosUpload(name);
  }

  Future<Response> getItemDetails(String barcode) async {
    return _apiProvider.getDocument('Item', barcode.substring(0, 7));
  }
}
