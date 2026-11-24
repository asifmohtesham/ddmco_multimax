import 'dart:io';
import 'dart:typed_data';

import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:path/path.dart' as p;

Future<bool> canUploadSharedItemImage(ApiProvider api, String itemCode) async {
  try {
    final response = await api.hasDocPermission('Item', itemCode, 'write');
    return ApiProvider.parseHasDocPermissionResponse(response.data);
  } catch (_) {
    return false;
  }
}

class ItemAlreadyHasImage implements Exception {
  const ItemAlreadyHasImage();
}

/// Saves one missing image. Keep a successful attachment for a retry if the
/// subsequent Item update fails while the upload sheet is open.
class SharedItemImageUpload {
  SharedItemImageUpload(this._api, this.itemCode);

  final ApiProvider _api;
  final String itemCode;
  String? _attachedUrl;

  bool get hasAttachment => _attachedUrl != null;

  Future<String> save(String photoPath) async {
    final encodedCode = Uri.encodeComponent(itemCode);
    final current = await _api.getDocument('Item', encodedCode);
    final record = _itemData(current.data);
    final currentImage = record['image'] as String?;
    if (currentImage != null && currentImage.trim().isNotEmpty) {
      if (currentImage == _attachedUrl) return currentImage;
      throw const ItemAlreadyHasImage();
    }

    final fileUrl = _attachedUrl ??= await _attach(photoPath);
    final result = await _api.updateDocument('Item', encodedCode, {
      'image': fileUrl,
      // Frappe checks the version read above before saving the Item.
      if (record['modified'] case final String modified) 'modified': modified,
    });
    if (_itemData(result.data)['image'] != fileUrl) {
      throw StateError('The Item response did not confirm the image');
    }
    return fileUrl;
  }

  Map _itemData(Object? response) => (response as Map)['data'] as Map;

  Future<String> _attach(String photoPath) async {
    Future<String> upload(String path) => _api.uploadFile(
      filePath: path,
      doctype: 'Item',
      docname: itemCode,
      fieldname: 'image',
    );

    final extension = p.extension(photoPath).toLowerCase();
    if (!const {'.jpg', '.jpeg', '.jfif'}.contains(extension)) {
      return upload(photoPath);
    }
    final bytes = await File(photoPath).readAsBytes();
    final stripped = _stripJpegExif(bytes);
    if (identical(stripped, bytes)) return upload(photoPath);

    final temporary = await Directory.systemTemp.createTemp('item_image_');
    final copy = File(p.join(temporary.path, p.basename(photoPath)));
    try {
      await copy.writeAsBytes(stripped);
      return await upload(copy.path);
    } finally {
      // The app owns this copy; the shared or picked original is left intact.
      try {
        if (await copy.exists()) await copy.delete();
        await temporary.delete();
      } on FileSystemException {
        // A cleanup failure must not make a successful upload look failed.
      }
    }
  }
}

/// Removes EXIF APP1 segments from ordinary JPEGs without decoding pixels.
/// Keep files with EXIF rotation or unrecognized application metadata intact.
Uint8List _stripJpegExif(Uint8List bytes) {
  if (bytes.length < 4) return bytes;
  final data = ByteData.sublistView(bytes);
  final endOfImage = bytes.length - 2;
  if (data.getUint16(0) != 0xffd8 || data.getUint16(endOfImage) != 0xffd9) {
    return bytes;
  }

  final output = BytesBuilder(copy: false);
  var cursor = 2;
  var copyFrom = 0;
  while (cursor + 4 <= endOfImage) {
    final markerStart = cursor;
    if (bytes[cursor++] != 0xff) return bytes;
    while (cursor < endOfImage && bytes[cursor] == 0xff) {
      cursor++;
    }
    if (cursor + 3 > endOfImage) return bytes;
    final marker = bytes[cursor++];
    final length = data.getUint16(cursor);
    final end = cursor + length;
    if (length < 2 || end > endOfImage) return bytes;
    final start = cursor + 2;

    if (marker == 0xda) {
      // Preserve the image's scan data, including all subsequent scans.
      if (copyFrom == 0) return bytes;
      output.add(Uint8List.sublistView(bytes, copyFrom));
      return output.takeBytes();
    }
    if (marker >= 0xe0 && marker <= 0xef) {
      bool hasSignature(String text) => _hasSignature(bytes, start, end, text);
      switch (marker) {
        case 0xe0:
          if (!hasSignature('JFIF\x00') && !hasSignature('JFXX\x00')) {
            return bytes;
          }
        case 0xe1:
          const signature = 'Exif\x00\x00';
          if (!hasSignature(signature) ||
              !_hasDefaultOrientation(
                ByteData.sublistView(bytes, start + signature.length, end),
              )) {
            return bytes;
          }
          output.add(Uint8List.sublistView(bytes, copyFrom, markerStart));
          copyFrom = end;
        case 0xe2:
          if (!hasSignature('ICC_PROFILE\x00')) return bytes;
        case 0xee:
          if (!hasSignature('Adobe')) return bytes;
        default:
          return bytes;
      }
    }
    cursor = end;
  }
  return bytes;
}

bool _hasSignature(Uint8List bytes, int start, int end, String signature) {
  if (end - start < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[start + i] != signature.codeUnitAt(i)) return false;
  }
  return true;
}

bool _hasDefaultOrientation(ByteData tiff) {
  if (tiff.lengthInBytes < 14) return false;
  final order = switch (tiff.getUint16(0)) {
    0x4949 => Endian.little,
    0x4d4d => Endian.big,
    _ => null,
  };
  if (order == null || tiff.getUint16(2, order) != 42) return false;
  final ifd = tiff.getUint32(4, order);
  if (ifd < 8 || ifd > tiff.lengthInBytes - 6) return false;
  final entryCount = tiff.getUint16(ifd, order);
  final entriesEnd = ifd + 2 + entryCount * 12;
  if (entriesEnd + 4 > tiff.lengthInBytes) return false;

  for (var entry = ifd + 2; entry < entriesEnd; entry += 12) {
    if (tiff.getUint16(entry, order) != 0x0112) continue;
    if (tiff.getUint16(entry + 2, order) != 3 ||
        tiff.getUint32(entry + 4, order) != 1 ||
        tiff.getUint16(entry + 8, order) != 1) {
      return false;
    }
  }
  return true;
}
