import 'dart:async';

import 'package:dio/dio.dart';
// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/item_model.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/services/scan_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/app_nav_drawer.dart';
import 'package:multimax/app/modules/global_widgets/camera_scan_overlay.dart';
import 'package:multimax/app/modules/global_widgets/doctype_image_upload.dart';
import 'package:multimax/app/modules/item/widgets/item_image.dart';
import 'package:multimax/app/modules/stock_sheet/logic/photo_decoder.dart';

typedef ShareItemDestination = ({String route, Object? arguments});

/// Returns true when Items from Photos takes ownership of the shared copy.
Future<bool> showShareItemQuickActions(
  BuildContext context, {
  required String photoPath,
  required bool showCamera,
}) async {
  final api = Get.find<ApiProvider>();
  final destination = await showModalBottomSheet<ShareItemDestination>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => ShareItemQuickActions(
      photoPath: photoPath,
      createDecoder: () => MlKitPhotoDecoder(scanAllFormats: true),
      lookup: Get.find<ScanService>().resolveItemBarcode,
      scan: showCamera ? CameraScanOverlay.show : null,
      canUpload: (itemCode) => canUploadSharedItemImage(api, itemCode),
      canOpenSuppliers: () => AppNavDrawerController.canOpenSuppliersByItem,
      upload: (context, itemCode) => showSharedItemImageUploadSheet(
        context,
        itemCode: itemCode,
        photoPath: photoPath,
      ),
      imageUrl: (path) => Uri.parse(api.baseUrl).resolve(path).toString(),
      onSelect: (destination) => Navigator.of(context).pop(destination),
    ),
  );
  if (destination == null ||
      !context.mounted ||
      !Get.find<AuthenticationController>().isAuthenticated.value) {
    return false;
  }
  if (destination.route == AppRoutes.ITEMS_FROM_PHOTOS) return true;
  unawaited(
    Get.toNamed<void>(
      destination.route,
      arguments: destination.arguments,
      preventDuplicates: false,
    ),
  );
  return false;
}

enum _Status {
  reading,
  unreadable,
  empty,
  choose,
  looking,
  missing,
  error,
  found,
}

class ShareItemQuickActions extends StatefulWidget {
  const ShareItemQuickActions({
    super.key,
    required this.photoPath,
    required this.createDecoder,
    required this.lookup,
    required this.canUpload,
    required this.canOpenSuppliers,
    required this.upload,
    required this.imageUrl,
    required this.onSelect,
    this.scan,
  });

  final String photoPath;
  final PhotoDecoder Function() createDecoder;
  final Future<Item?> Function(String barcode) lookup;
  final Future<bool> Function(String itemCode) canUpload;
  final bool Function() canOpenSuppliers;
  final Future<String?> Function(BuildContext, String itemCode) upload;
  final String Function(String path) imageUrl;
  final ValueChanged<ShareItemDestination> onSelect;
  final Future<String?> Function(BuildContext)? scan;

  @override
  State<ShareItemQuickActions> createState() => _ShareItemQuickActionsState();
}

class _ShareItemQuickActionsState extends State<ShareItemQuickActions> {
  _Status _status = _Status.reading;
  List<String> _barcodes = const [];
  String? _selectedBarcode;
  Item? _item;
  String? _image;
  bool _canUpload = false;
  bool _openingUpload = false;
  bool _cameraOpen = false;
  String _lookupError = '';

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  Future<void> _decode() async {
    List<String>? values;
    try {
      final decoder = widget.createDecoder();
      try {
        final whole = await decoder.readWhole(widget.photoPath);
        if (!mounted) return;
        if (whole != null) {
          values = _distinctCodes(whole);
          if (values.isEmpty) {
            final zoomed = await decoder.zoomIn(
              widget.photoPath,
              whole: whole,
              stopped: () => !mounted,
            );
            values = _distinctCodes(zoomed ?? whole);
          }
        }
      } finally {
        await decoder.dispose();
      }
    } catch (_) {
      values = null;
    }
    if (!mounted) return;
    if (values != null && values.length == 1) {
      await _lookup(values.single);
      return;
    }
    setState(() {
      _barcodes = values ?? const [];
      _status = values == null
          ? _Status.unreadable
          : values.isEmpty
          ? _Status.empty
          : _Status.choose;
    });
  }

  List<String> _distinctCodes(List<String> values) => {
    for (final raw in values)
      if (raw.trim().isNotEmpty) raw.trim(),
  }.toList();

  Future<void> _lookup(String barcode) async {
    if (_status == _Status.looking) return;
    setState(() {
      _selectedBarcode = barcode;
      _status = _Status.looking;
    });
    try {
      final item = await widget.lookup(barcode);
      if (!mounted) return;
      final image = item?.image?.trim();
      final hasImage = image != null && image.isNotEmpty;
      final canUpload =
          item != null &&
          !hasImage &&
          await widget.canUpload(_documentName(item));
      if (!mounted) return;
      setState(() {
        _item = item;
        _image = hasImage ? image : null;
        _canUpload = canUpload;
        _status = item == null ? _Status.missing : _Status.found;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _lookupError = _readableLookupError(error);
        _status = _Status.error;
      });
    }
  }

  Future<void> _scan() async {
    if (_cameraOpen) return;
    final scan = widget.scan;
    if (scan == null) return;
    setState(() => _cameraOpen = true);
    try {
      final barcode = (await scan(context))?.trim();
      if (mounted && barcode != null && barcode.isNotEmpty) {
        await _lookup(barcode);
      }
    } finally {
      if (mounted) setState(() => _cameraOpen = false);
    }
  }

  Future<void> _uploadImage(String itemCode) async {
    if (_openingUpload) return;
    setState(() => _openingUpload = true);
    try {
      final image = await widget.upload(context, itemCode);
      if (mounted && image != null) setState(() => _image = image);
    } finally {
      if (mounted) setState(() => _openingUpload = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_status != _Status.found)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Item quick actions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ..._buildState(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Items from Photos'),
              subtitle: const Text('Use this photo'),
              onTap: () => widget.onSelect((
                route: AppRoutes.ITEMS_FROM_PHOTOS,
                arguments: [widget.photoPath],
              )),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildState() => switch (_status) {
    _Status.reading => [_loading('Reading barcode…')],
    _Status.looking => [_loading('Looking up Item…')],
    _Status.unreadable => [
      _message("Couldn't read this photo."),
      if (widget.scan != null) _cameraTile(),
    ],
    _Status.empty => [
      _message('No barcode found in this photo.'),
      if (widget.scan != null) _cameraTile(),
    ],
    _Status.choose => [
      _message('Choose a barcode from this photo.'),
      for (final barcode in _barcodes)
        ListTile(
          leading: const Icon(Icons.qr_code),
          title: Text(barcode),
          onTap: () => _lookup(barcode),
        ),
    ],
    _Status.missing => [
      _message('No Item matches this barcode.\n$_selectedBarcode'),
      if (_barcodes.length > 1) _chooseAnotherTile(),
    ],
    _Status.error => [
      _message(_lookupError),
      ListTile(
        leading: const Icon(Icons.refresh),
        title: const Text('Retry lookup'),
        onTap: () {
          final barcode = _selectedBarcode;
          if (barcode != null) unawaited(_lookup(barcode));
        },
      ),
      if (_barcodes.length > 1) _chooseAnotherTile(),
    ],
    _Status.found => _itemActions(_item!),
  };

  List<Widget> _itemActions(Item item) {
    final documentName = _documentName(item);
    final filters = SuppliersByItemFilters.forScannedItem(
      // The report's Items Link filter expects the ERPNext document name.
      itemCode: documentName,
      variantOf: item.variantOf,
    );
    final template = filters.variantOf.firstOrNull;
    final image = _image;
    return [
      ListTile(
        leading: ItemImage(
          imageUrl: image == null ? null : widget.imageUrl(image),
          size: 48,
        ),
        title: Text(item.itemName.isEmpty ? item.itemCode : item.itemName),
        subtitle: Text(
          [
            if (item.itemName.isNotEmpty) item.itemCode,
            if (template != null) 'Variant of $template',
          ].join('\n'),
        ),
        isThreeLine: item.itemName.isNotEmpty && template != null,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => widget.onSelect((
          route: AppRoutes.ITEM_FORM,
          arguments: {'itemCode': documentName},
        )),
      ),
      const Divider(height: 1),
      if (image == null && _canUpload)
        ListTile(
          leading: const Icon(Icons.add_photo_alternate_outlined),
          title: const Text('Upload Item Image'),
          enabled: !_openingUpload,
          onTap: _openingUpload ? null : () => _uploadImage(documentName),
        ),
      Obx(() {
        if (!widget.canOpenSuppliers()) return const SizedBox.shrink();
        return ListTile(
          leading: const Icon(Icons.local_shipping_outlined),
          title: Text(
            template != null ? 'Suppliers by Item' : 'Suppliers for this Item',
          ),
          subtitle: Text(
            template != null ? 'All variants of $template' : item.itemCode,
          ),
          onTap: () {
            if (!widget.canOpenSuppliers()) return;
            widget.onSelect((
              route: AppRoutes.SUPPLIERS_BY_ITEM,
              arguments: filters,
            ));
          },
        );
      }),
      if (_barcodes.length > 1) _chooseAnotherTile(),
    ];
  }

  Widget _message(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Semantics(liveRegion: true, child: Text(text)),
  );

  Widget _loading(String text) => ListTile(
    leading: const SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    title: Text(text),
  );

  Widget _chooseAnotherTile() => ListTile(
    leading: const Icon(Icons.qr_code),
    title: const Text('Choose another barcode'),
    onTap: () => setState(() => _status = _Status.choose),
  );

  Widget _cameraTile() => ListTile(
    leading: const Icon(Icons.qr_code_scanner),
    title: const Text('Scan with camera'),
    enabled: !_cameraOpen,
    onTap: _cameraOpen ? null : _scan,
  );
}

String _documentName(Item item) =>
    item.name.isEmpty ? item.itemCode : item.name;

String _readableLookupError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    if (status == 401 ||
        status == 403 ||
        (body is Map && body['exc_type'] == 'PermissionError')) {
      return "You don't have permission to look up this Item.";
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Could not reach the server. Check your connection and try again.';
    }
  }
  return 'Could not look up this Item. Try again.';
}
