import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/file_download_button.dart';

/// A rounded item thumbnail. Shows the network image when [imageUrl] is
/// non-empty, otherwise a 2-letter initials fallback derived from the item
/// name (or code). Tapping an actual image opens [showItemImagePreview]
/// without leaving the current screen.
class ItemThumbnail extends StatelessWidget {
  final String? imageUrl;
  final String itemCode;
  final String itemName;
  final double size;

  const ItemThumbnail({
    super.key,
    required this.imageUrl,
    required this.itemCode,
    required this.itemName,
    this.size = 46,
  });

  String get _initials {
    final source = itemName.trim().isNotEmpty ? itemName : itemCode;
    final words = source
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '·';
    final letters = words.take(2).map((w) => w[0]).join();
    return letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget fallback() => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: cs.secondaryContainer,
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: cs.onSecondaryContainer,
        ),
      ),
    );

    final url = imageUrl?.trim() ?? '';
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? fallback()
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder: (_, __) => fallback(),
                errorWidget: (_, __, ___) => fallback(),
              ),
      ),
    );

    if (url.isEmpty) return thumb;
    return GestureDetector(
      onTap: () => showItemImagePreview(
        context,
        url,
        itemCode,
        itemName,
        heroTag: 'item-image-$itemCode',
      ),
      child: Hero(tag: 'item-image-$itemCode', child: thumb),
    );
  }
}

/// Opens a fullscreen route above the calling sheet, form, or report.
void showItemImagePreview(
  BuildContext context,
  String url,
  String itemCode,
  String itemName, {
  String? fileName,
  Object? heroTag,
}) {
  showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => ItemImagePreview(
      url: url,
      title: [itemCode, itemName].where((text) => text.isNotEmpty).join(' · '),
      fileName: fileName,
      heroTag: heroTag,
    ),
  );
}

class ItemImagePreview extends StatefulWidget {
  const ItemImagePreview({
    super.key,
    required this.url,
    required this.title,
    this.fileName,
    this.heroTag,
    this.navigationActions = const [],
  });

  final String url;
  final String title;
  final String? fileName;
  final Object? heroTag;
  final List<Widget> navigationActions;

  @override
  State<ItemImagePreview> createState() => _ItemImagePreviewState();
}

class _ItemImagePreviewState extends State<ItemImagePreview>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  final _viewerKey = GlobalKey();
  final _imageKey = GlobalKey();
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => _transform.value = _zoom!.value);
  Animation<Matrix4>? _zoom;
  Offset _tap = Offset.zero;
  Future<Uint8List>? _privateImage;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_keepImageVisible);
    final uri = Uri.tryParse(widget.url);
    if (uri?.path.startsWith('/private/files/') ?? false) {
      _privateImage = Get.find<ApiProvider>().getFileBytes(widget.url);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom(Size viewport) {
    final target = Matrix4.identity();
    if (_transform.value.getMaxScaleOnAxis() <= 1.01) {
      const scale = 2.5;
      final imagePoint = _transform.toScene(_tap);
      final offset = _tap - imagePoint * scale;
      // Direct controller writes bypass InteractiveViewer's boundary checks.
      // Use the same zero-margin bounds as the interactive pan.
      target
        ..translateByDouble(
          offset.dx.clamp(viewport.width * (1 - scale), 0).toDouble(),
          offset.dy.clamp(viewport.height * (1 - scale), 0).toDouble(),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, scale, 1);
    }
    _zoom = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).chain(CurveTween(curve: Curves.easeInOut)).animate(_animation);
    _animation.forward(from: 0);
  }

  void _keepImageVisible() {
    final viewer = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final image = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewer == null || !viewer.hasSize || image == null || !image.hasSize) {
      return;
    }
    final viewport = viewer.size;
    final size = image.size;
    final matrix = _transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final translation = matrix.getTranslation();

    // InteractiveViewer bounds the whole child, including the letterboxing.
    // Keep the image visible even when its short edge fits inside the viewport.
    double clampAxis(double offset, double extent, double imageExtent) {
      final start = (extent - imageExtent) * scale / 2;
      final length = imageExtent * scale;
      final visible = math.min(length, extent / 2);
      return offset.clamp(visible - start - length, extent - visible - start);
    }

    final dx = clampAxis(translation.x, viewport.width, size.width);
    final dy = clampAxis(translation.y, viewport.height, size.height);
    if (dx != translation.x || dy != translation.y) {
      _transform.value = matrix.clone()
        ..setTranslationRaw(dx, dy, translation.z);
    }
  }

  Widget _onImageFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool synchronous,
  ) {
    if (frame == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keepImageVisible();
      });
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const loading = Center(child: CircularProgressIndicator(strokeWidth: 2));
    final error = Icon(
      Icons.broken_image_outlined,
      size: 64,
      color: colors.onSurfaceVariant,
    );
    final privateImage = _privateImage;
    final image = privateImage == null
        ? CachedNetworkImage(
            imageUrl: widget.url,
            imageBuilder: (_, provider) => Image(
              key: _imageKey,
              image: provider,
              fit: BoxFit.contain,
              frameBuilder: _onImageFrame,
            ),
            placeholder: (_, __) => loading,
            errorWidget: (_, __, ___) => error,
          )
        : FutureBuilder<Uint8List>(
            future: privateImage,
            builder: (_, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return loading;
              }
              final bytes = snapshot.data;
              return bytes == null
                  ? error
                  : Image.memory(
                      bytes,
                      key: _imageKey,
                      fit: BoxFit.contain,
                      frameBuilder: _onImageFrame,
                      errorBuilder: (_, __, ___) => error,
                    );
            },
          );

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text(widget.title),
        leading: CloseButton(onPressed: () => Navigator.of(context).pop()),
        actions: [
          ...widget.navigationActions,
          FileDownloadButton(url: widget.url, fileName: widget.fileName),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (_, constraints) => GestureDetector(
            onDoubleTapDown: (details) => _tap = details.localPosition,
            onDoubleTap: () => _toggleZoom(constraints.biggest),
            child: InteractiveViewer(
              key: _viewerKey,
              transformationController: _transform,
              minScale: 1,
              maxScale: 5,
              panAxis: PanAxis.free,
              onInteractionStart: (_) => _animation.stop(),
              child: SizedBox.expand(
                child: Center(
                  child: widget.heroTag == null
                      ? image
                      : Hero(tag: widget.heroTag!, child: image),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
