import 'package:dio/dio.dart';
// Keep the Flutter Material import used throughout the app.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multimax/app/modules/stock_sheet/model/items_from_photos_models.dart';

class ItemImageViewer extends StatefulWidget {
  const ItemImageViewer({
    super.key,
    required this.item,
    required this.cachedBytes,
    required this.load,
  });

  final ItemInfo item;
  final Uint8List? cachedBytes;
  final Future<Uint8List> Function({required bool refresh}) load;

  @override
  State<ItemImageViewer> createState() => _ItemImageViewerState();
}

class _ItemImageViewerState extends State<ItemImageViewer> {
  Uint8List? _bytes;
  bool _loading = false;
  String? _failureReason;

  @override
  void initState() {
    super.initState();
    _bytes = widget.cachedBytes;
    if (_bytes == null) _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _bytes = null;
      _failureReason = null;
    });
    try {
      _bytes = await widget.load(refresh: refresh);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      _failureReason = status != null
          ? 'The server returned HTTP $status.'
          : switch (error.type) {
              DioExceptionType.connectionError =>
                'Could not connect to the server.',
              DioExceptionType.connectionTimeout ||
              DioExceptionType.receiveTimeout ||
              DioExceptionType.sendTimeout => 'The request timed out.',
              _ => null,
            };
    } on FormatException {
      _failureReason = 'The server returned an empty image.';
    } on Exception {
      // The error state offers another attempt.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _error({bool invalidImage = false}) {
    final reason = invalidImage
        ? 'The image could not be decoded.'
        : _failureReason;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Couldn't load the image."),
            if (reason != null) Text(reason, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : () => _load(refresh: invalidImage),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    final bytes = _bytes;
    void close() => Navigator.of(context).maybePop();

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): close},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colours.surface,
          appBar: AppBar(
            backgroundColor: colours.surface,
            foregroundColor: colours.onSurface,
            leading: IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: close,
            ),
            title: Text(widget.item.itemCode),
          ),
          body: SafeArea(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: colours.onSurface),
                        const SizedBox(height: 12),
                        const Text('Loading image…'),
                      ],
                    ),
                  )
                : bytes == null
                ? _error()
                : InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: SizedBox.expand(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => _error(invalidImage: true),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
