import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:image_picker/image_picker.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:multimax/app/modules/global_widgets/item_image.dart';
import 'package:multimax/app/shared/item_sheet/shared_item_image_upload.dart';

export 'package:multimax/app/shared/item_sheet/shared_item_image_upload.dart'
    show canUploadSharedItemImage;

/// Reusable image-field widget for any Frappe DocType.
///
/// Shows the current image (tap to full-screen) with an always-visible Edit
/// badge. Tapping the badge opens a camera / gallery / remove picker.
/// Permissions are enforced server-side by Frappe's upload_file endpoint,
/// mirroring ERPNext desktop behaviour exactly.
class DocTypeImageUpload extends StatefulWidget {
  final String doctype;
  final String docname;
  final String fieldname;
  final String baseUrl;
  final String? imageUrl;

  /// Called after a successful upload OR removal so the parent can refresh
  /// its document data. Use `() { controller.fetchDocument(); }` at call sites
  /// to discard the returned Future and satisfy VoidCallback's type.
  final VoidCallback onUploaded;

  const DocTypeImageUpload({
    super.key,
    required this.doctype,
    required this.docname,
    required this.fieldname,
    required this.baseUrl,
    required this.imageUrl,
    required this.onUploaded,
  });

  @override
  State<DocTypeImageUpload> createState() => _DocTypeImageUploadState();
}

class _DocTypeImageUploadState extends State<DocTypeImageUpload> {
  bool _isUploading = false;
  final _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 200,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Image or placeholder ────────────────────────────────────────
          if (widget.imageUrl != null)
            GestureDetector(
              onTap: () => showItemImagePreview(
                context,
                Uri.parse(widget.baseUrl).resolve(widget.imageUrl!).toString(),
                widget.docname,
                '',
              ),
              child: Image.network(
                '${widget.baseUrl}${widget.imageUrl}',
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                          : null,
                      color: cs.primary,
                      strokeWidth: 2,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 50,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 50,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),

          // ── Upload progress overlay ─────────────────────────────────────
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(color: cs.primary, strokeWidth: 2),
              ),
            ),

          // ── Edit badge ──────────────────────────────────────────────────
          if (!_isUploading)
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _showSourcePicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showSourcePicker(BuildContext context) async {
    final source = await _showImageSourcePicker(
      context,
      onRemove: widget.imageUrl == null ? null : _removeImage,
    );
    if (source != null && mounted) await _pickAndUpload(source);
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final file = await _picker.pickImage(source: source);
    if (file == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      await Get.find<ApiProvider>().uploadFile(
        filePath: file.path,
        doctype: widget.doctype,
        docname: widget.docname,
        fieldname: widget.fieldname,
      );
      if (mounted) widget.onUploaded();
    } catch (e) {
      GlobalSnackbar.error(message: _errorMessage(e));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _removeImage() async {
    if (!mounted) return;
    setState(() => _isUploading = true);
    try {
      await Get.find<ApiProvider>().updateDocument(
        widget.doctype,
        widget.docname,
        {widget.fieldname: null},
      );
      if (mounted) widget.onUploaded();
    } catch (e) {
      GlobalSnackbar.error(message: _errorMessage(e));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 403) {
        return 'You do not have permission to edit this document';
      }
      return 'Upload failed. Check your connection.';
    }
    return 'An unexpected error occurred.';
  }
}

Future<ImageSource?> _showImageSourcePicker(
  BuildContext context, {
  VoidCallback? onRemove,
}) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              subtitle: const Text('Open camera'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            Divider(height: 1, color: cs.outlineVariant),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Pick from device'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            if (onRemove != null) ...[
              Divider(height: 1, color: cs.outlineVariant),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Remove Image', style: TextStyle(color: cs.error)),
                subtitle: const Text('Clears the image field'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onRemove();
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Previews the shared image and returns the saved Item image URL on success.
Future<String?> showSharedItemImageUploadSheet(
  BuildContext context, {
  required String itemCode,
  required String photoPath,
  ApiProvider? api,
  Future<XFile?> Function(ImageSource)? pickImage,
}) {
  final upload = SharedItemImageUpload(
    api ?? Get.find<ApiProvider>(),
    itemCode,
  );
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => _SharedItemImageUploadSheet(
      photoPath: photoPath,
      upload: upload,
      pickImage:
          pickImage ?? (source) => ImagePicker().pickImage(source: source),
    ),
  );
}

class _SharedItemImageUploadSheet extends StatefulWidget {
  const _SharedItemImageUploadSheet({
    required this.photoPath,
    required this.upload,
    required this.pickImage,
  });

  final String photoPath;
  final SharedItemImageUpload upload;
  final Future<XFile?> Function(ImageSource) pickImage;

  @override
  State<_SharedItemImageUploadSheet> createState() =>
      _SharedItemImageUploadSheetState();
}

class _SharedItemImageUploadSheetState
    extends State<_SharedItemImageUploadSheet> {
  late String _photoPath = widget.photoPath;
  bool _isPicking = false;
  bool _isSaving = false;
  String? _error;

  bool get _busy => _isPicking || _isSaving;

  Future<void> _pickAnother() async {
    if (_busy || widget.upload.hasAttachment) return;
    setState(() => _isPicking = true);
    try {
      final source = await _showImageSourcePicker(context);
      if (source == null || !mounted) return;
      final photo = await widget.pickImage(source);
      if (photo == null || !mounted) return;
      setState(() {
        _photoPath = photo.path;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the photo picker.');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final fileUrl = await widget.upload.save(_photoPath);
      if (mounted) Navigator.pop(context, fileUrl);
    } catch (error) {
      if (mounted) setState(() => _error = _uploadError(error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _uploadError(Object error) {
    if (error is ItemAlreadyHasImage) {
      return 'This Item already has an image.';
    }
    if (error is DioException) {
      switch (error.response?.statusCode) {
        case 401:
        case 403:
          return 'You do not have permission to update this Item image.';
        case 413:
          return 'This photo is too large. Pick another photo.';
      }
    }
    if (widget.upload.hasAttachment) {
      return 'The photo was attached, but the Item image could not be saved. Try again.';
    }
    return 'Could not upload the photo. Try again or pick another photo.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Upload Item Image', style: theme.textTheme.titleLarge),
              Text(widget.upload.itemCode, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * 0.36)
                    .clamp(0.0, 300.0)
                    .toDouble(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: theme.colorScheme.surfaceContainer,
                    child: Image.file(
                      File(_photoPath),
                      fit: BoxFit.contain,
                      cacheWidth: 960,
                      semanticLabel: 'Item image preview',
                      errorBuilder: (_, _, _) =>
                          const Center(child: Text('Preview unavailable')),
                    ),
                  ),
                ),
              ),
              if (_error case final error?) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || widget.upload.hasAttachment
                        ? null
                        : _pickAnother,
                    child: const Text('Pick Another'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _isSaving
                        ? SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : const Icon(Icons.file_upload_outlined),
                    label: Text(
                      _isSaving
                          ? 'Uploading…'
                          : widget.upload.hasAttachment
                          ? 'Retry'
                          : 'Upload',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
