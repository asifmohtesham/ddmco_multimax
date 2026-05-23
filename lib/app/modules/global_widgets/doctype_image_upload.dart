import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:image_picker/image_picker.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

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
              onTap: () => _openFullScreen(context, '${widget.baseUrl}${widget.imageUrl}'),
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

  void _showSourcePicker(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              subtitle: const Text('Open camera'),
              onTap: () {
                Get.back();
                _pickAndUpload(ImageSource.camera);
              },
            ),
            Divider(height: 1, color: cs.outlineVariant),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Pick from device'),
              onTap: () {
                Get.back();
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            if (widget.imageUrl != null) ...[
              Divider(height: 1, color: cs.outlineVariant),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Remove Image', style: TextStyle(color: cs.error)),
                subtitle: const Text('Clears the image field'),
                onTap: () {
                  Get.back();
                  _removeImage();
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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

  void _openFullScreen(BuildContext context, String url) {
    Get.dialog(
      barrierDismissible: true,
      barrierColor: Colors.black87,
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
              Get.back();
            }
          },
          child: Stack(
            children: [
              InteractiveViewer(
                child: Center(
                  child: Image.network(
                    url,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: Get.back,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
