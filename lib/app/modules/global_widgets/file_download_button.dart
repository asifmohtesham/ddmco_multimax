import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
// Keep the Material import used by the app's supported Flutter SDKs.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

/// Downloads an ERPNext file using the current session, then saves or shares it.
class FileDownloadButton extends StatefulWidget {
  const FileDownloadButton({
    super.key,
    required this.url,
    this.fileName,
    this.isImage = true,
    this.shareOnly = false,
  });

  final String url;
  final String? fileName;
  final bool isImage;
  final bool shareOnly;

  @override
  State<FileDownloadButton> createState() => _FileDownloadButtonState();
}

class _FileDownloadButtonState extends State<FileDownloadButton> {
  final _busy = false.obs;

  Future<void> _download() async {
    if (_busy.value) return;
    _busy.value = true;
    final shareOnly = widget.shareOnly;
    final isImage = widget.isImage;
    final platform = defaultTargetPlatform;
    try {
      final name = _fileName(widget.url, widget.fileName);
      final bytes = await Get.find<ApiProvider>().getFileBytes(widget.url);
      if (!mounted) return;
      if (bytes.isEmpty) throw const FormatException('Empty file response');

      final mobile =
          platform == TargetPlatform.android || platform == TargetPlatform.iOS;
      if (!shareOnly && isImage && !kIsWeb && mobile) {
        try {
          await Gal.putImageBytes(
            bytes,
            // Android detects and appends the extension from the image data.
            name: platform == TargetPlatform.android
                ? path.basenameWithoutExtension(name)
                : name,
          );
          GlobalSnackbar.success(
            message: platform == TargetPlatform.iOS
                ? 'Image saved to Photos.'
                : 'Image saved to Pictures.',
          );
          return;
        } on Exception {
          // Offer the original file through the share sheet if Photos fails.
          if (!mounted) return;
        }
      }

      final file = XFile.fromData(bytes, name: name);
      if (!kIsWeb &&
          !mobile &&
          (!shareOnly || platform == TargetPlatform.linux)) {
        final destination = await getSaveLocation(suggestedName: name);
        if (destination == null) return;
        await file.saveTo(destination.path);
        GlobalSnackbar.success(message: 'File saved.');
      } else {
        if (!mounted) return;
        final box = context.findRenderObject() as RenderBox?;
        final origin = box != null && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : null;
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [file],
            fileNameOverrides: [name],
            sharePositionOrigin: origin,
          ),
        );
        if (result.status == ShareResultStatus.success) {
          GlobalSnackbar.success(message: 'File ready.');
        } else if (result.status == ShareResultStatus.unavailable) {
          if (!kIsWeb) throw StateError('File sharing is unavailable');
          // share_plus reports a browser download as unavailable sharing.
          GlobalSnackbar.success(message: 'Browser download requested.');
        }
      }
    } catch (_) {
      GlobalSnackbar.error(
        message: 'Could not download or save the file. Try again.',
      );
    } finally {
      _busy.value = false;
    }
  }

  String _fileName(String url, String? providedName) {
    final segments = Uri.tryParse(url)?.pathSegments;
    final urlName = segments == null || segments.isEmpty ? '' : segments.last;
    final name = providedName?.trim();
    final safeName = (name == null || name.isEmpty ? urlName : name)
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim();
    return safeName.isEmpty || safeName == '.' || safeName == '..'
        ? 'download'
        : safeName;
  }

  @override
  Widget build(BuildContext context) => AsyncIconButton(
    busy: _busy,
    onPressed: _download,
    tooltip: widget.shareOnly ? 'Share file' : 'Download',
    icon: Icon(widget.shareOnly ? Icons.share : Icons.download_outlined),
  );
}
