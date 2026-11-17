import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/fix_code_sheet.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/out_of_stock_sheet.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/review_list.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/stock_sheet_result_list.dart';

/// Returns the paths of the photos taken or picked; empty when cancelled.
typedef PhotoPicker = Future<List<String>> Function();

Future<List<String>> _takePhoto() async {
  final photo = await ImagePicker().pickImage(source: ImageSource.camera);
  return photo == null ? const [] : [photo.path];
}

Future<List<String>> _chooseFromGallery() async {
  final photos = await ImagePicker().pickMultiImage();
  return [for (final photo in photos) photo.path];
}

enum _AddSource { camera, gallery }

/// Shared photos → stock sheet. Reads the photos on open, shows progress,
/// then the review list (reorder, switch off, fix codes, add photos, pick
/// the format), asks about out-of-stock items when there are any, then shows
/// the result.
///
/// Stateful (not a GetView) because it drives the share, the out-of-stock
/// sheet and the new-share question from workers on the controller, which
/// need this screen's lifetime and context.
class StockSheetScreen extends StatefulWidget {
  const StockSheetScreen({
    super.key,
    this.paths,
    this.pickCamera = _takePhoto,
    this.pickGallery = _chooseFromGallery,
  });

  /// The shared photo paths; null takes them from the route arguments.
  final List<String>? paths;

  /// ＋ → Take a photo.
  final PhotoPicker pickCamera;

  /// ＋ → Choose from gallery.
  final PhotoPicker pickGallery;

  @override
  State<StockSheetScreen> createState() => _StockSheetScreenState();
}

class _StockSheetScreenState extends State<StockSheetScreen> {
  final StockSheetController controller = Get.find<StockSheetController>();
  final List<Worker> _workers = [];

  /// Bumped when this screen closes the sheets above it for a new share, so
  /// the out-of-stock sheet's late (null) answer is ignored.
  int _sheetEpoch = 0;

  bool _askingPending = false;
  bool _askingDiscard = false;

  @override
  void initState() {
    super.initState();
    _workers
      ..add(ever<int>(controller.shareSerial, (_) => _startShare()))
      ..add(
        ever<StockSheetPhase>(controller.phase, (phase) {
          if (phase == StockSheetPhase.awaitingChoice) _askOutOfStock();
        }),
      )
      ..add(
        ever<List<String>>(controller.pendingShare, (paths) {
          if (paths.isNotEmpty) _askPendingShare();
        }),
      );
    final paths = widget.paths ?? _argumentPaths();
    if (paths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.offerShare(paths);
      });
    }
  }

  @override
  void dispose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    super.dispose();
  }

  static List<String> _argumentPaths() {
    final args = Get.arguments;
    return args is List ? args.whereType<String>().toList() : const [];
  }

  /// Closes any sheet, menu or dialog open above this screen. Their pending
  /// answers are then ignored (see [_sheetEpoch] and the share serial).
  void _closeSheetsAbove() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive || route.isCurrent) return;
    Navigator.of(context).popUntil((r) => r == route);
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent) Navigator.of(context).pop();
  }

  bool get _reviewing => switch (controller.phase.value) {
    StockSheetPhase.reviewing || StockSheetPhase.awaitingChoice => true,
    _ => false,
  };

  Future<void> _startShare() async {
    if (!mounted) return;
    _closeSheetsAbove();
    // Over the photo limit, the controller refuses it with its message.
    await controller.start(controller.sharedPaths.toList());
  }

  Future<void> _askOutOfStock() async {
    if (!mounted) return;
    final serial = controller.shareSerial.value;
    final epoch = _sheetEpoch;
    final count = controller.result.value?.outOfStockCount ?? 0;
    final choice = await showOutOfStockSheet(context, count: count);
    if (!mounted || serial != controller.shareSerial.value) return;
    if (epoch != _sheetEpoch) return;
    if (controller.phase.value != StockSheetPhase.awaitingChoice) return;
    // Dismissed (null), it goes back to the review.
    await controller.chooseOutOfStock(choice);
  }

  /// A share arrived during the review: add it, start again, or drop it.
  /// The question shows over whatever is open; Add and Start again close
  /// that first, so its answer cannot act on the new state.
  Future<void> _askPendingShare() async {
    if (!mounted || _askingPending) return;
    _askingPending = true;
    final PendingShareChoice choice;
    try {
      choice =
          await showDialog<PendingShareChoice>(
            context: context,
            builder: (_) => _PendingShareDialog(controller: controller),
          ) ??
          PendingShareChoice.cancel;
    } finally {
      _askingPending = false;
    }
    if (!mounted) return;
    if (choice != PendingShareChoice.cancel) {
      _sheetEpoch++;
      _closeSheetsAbove();
    }
    await controller.resolvePendingShare(choice);
  }

  /// Back during the review: the photos go only if the user says so. The
  /// controller's onClose cleans up once the screen has gone.
  Future<void> _confirmDiscard() async {
    if (_askingDiscard) return;
    _askingDiscard = true;
    final bool? discard;
    try {
      discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard these photos?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep reviewing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
    } finally {
      _askingDiscard = false;
    }
    if (discard != true || !mounted) return;
    _closeSheetsAbove();
    _close();
  }

  void _fix(int index, String? noteBarcode) {
    showFixCodeSheet(
      context,
      onSubmit: (code) =>
          controller.fixCode(index, code, noteBarcode: noteBarcode),
    );
  }

  Future<void> _add(_AddSource source) async {
    if (controller.adding.value) return;
    final pick = source == _AddSource.camera
        ? widget.pickCamera
        : widget.pickGallery;
    final List<String> paths;
    try {
      paths = await pick();
    } catch (e, st) {
      if (kDebugMode) debugPrint('StockSheetScreen: pick failed: $e\n$st');
      AppNotification.warning(
        source == _AddSource.camera
            ? "Couldn't open the camera."
            : "Couldn't open the gallery.",
      );
      return;
    }
    if (!mounted || paths.isEmpty) return;
    final error = await controller.addPhotos(paths);
    if (mounted && error != null) AppNotification.warning(error);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final reviewing = _reviewing;
      return PopScope(
        canPop: !reviewing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDiscard();
        },
        child: Scaffold(
          appBar: reviewing
              ? _reviewAppBar()
              : AppBar(title: const Text('Stock sheet')),
          body: Obx(_body),
          bottomNavigationBar: Obx(_footer),
        ),
      );
    });
  }

  PreferredSizeWidget _reviewAppBar() {
    return AppBar(
      title: Obx(() {
        final photos = controller.review.length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Review photos'),
            Text(
              '$photos photo${photos == 1 ? '' : 's'} · '
              '${controller.sheetPhotoCount} on the sheet',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        );
      }),
      actions: [
        // Its own Obx, so the icon → spinner swap repaints while adding.
        Obx(() {
          final adding = controller.adding.value;
          return PopupMenuButton<_AddSource>(
            tooltip: 'Add photos',
            enabled: !adding,
            onSelected: _add,
            icon: adding
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: IconTheme.of(context).color,
                    ),
                  )
                : const Icon(Icons.add),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _AddSource.camera,
                child: ListTile(
                  leading: Icon(Icons.photo_camera_outlined),
                  title: Text('Take a photo'),
                ),
              ),
              PopupMenuItem(
                value: _AddSource.gallery,
                child: ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('Choose from gallery'),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _body() {
    switch (controller.phase.value) {
      case StockSheetPhase.idle:
        return const SizedBox.shrink();
      case StockSheetPhase.decoding:
        final total = controller.total.value;
        final decoded = controller.decoded.value;
        return _Progress(
          value: total == 0 ? null : decoded / total,
          label: 'Reading photo ${math.min(decoded + 1, total)} of $total',
        );
      case StockSheetPhase.checkingStock:
        return const _Progress(label: 'Checking stock…');
      case StockSheetPhase.reviewing:
      case StockSheetPhase.awaitingChoice:
        // The list stays behind the out-of-stock question.
        return ReviewList(
          entries: controller.review.toList(),
          thumbnails: Map.of(controller.thumbnails),
          onReorder: controller.reorder,
          onToggle: controller.setIncluded,
          onToggleItem: controller.setItemIncluded,
          onFix: _fix,
          onRetryCheck: controller.retryCheck,
          recheckBusy: controller.rechecking,
        );
      case StockSheetPhase.building:
        return const _Progress(label: 'Building file…');
      case StockSheetPhase.done:
        final result = controller.result.value;
        if (result == null) return const SizedBox.shrink();
        return StockSheetResultList(
          result: result,
          // The photos on the sheet, as in the file's subtitle.
          photoCount: controller.sheetPhotoCount,
          thumbnails: Map.of(controller.thumbnails),
        );
      case StockSheetPhase.error:
        return _ErrorMessage(
          message: controller.errorMessage.value ?? 'Something went wrong.',
        );
    }
  }

  Widget _footer() {
    switch (controller.phase.value) {
      case StockSheetPhase.reviewing:
      case StockSheetPhase.awaitingChoice:
        final n = controller.sheetPhotoCount;
        final label = 'Make sheet · $n photo${n == 1 ? '' : 's'}';
        const icon = Icon(Icons.description_outlined);
        // Nothing on the sheet, or the list still changing: makeSheet would
        // refuse, so the button says so by being disabled.
        final blocked =
            n == 0 || controller.adding.value || controller.rechecking.value;
        return _ActionBar(
          top: SegmentedButton<SheetFormat>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: SheetFormat.excel,
                icon: Icon(Icons.table_chart_outlined),
                label: Text('Excel'),
              ),
              ButtonSegment(
                value: SheetFormat.pdf,
                icon: Icon(Icons.picture_as_pdf_outlined),
                label: Text('PDF'),
              ),
              ButtonSegment(
                value: SheetFormat.both,
                icon: Icon(Icons.library_books_outlined),
                label: Text('Both'),
              ),
            ],
            selected: {controller.format.value},
            onSelectionChanged: (picked) =>
                controller.format.value = picked.single,
          ),
          message: controller.errorMessage.value,
          children: [
            Expanded(
              child: blocked
                  ? FilledButton.icon(
                      onPressed: null,
                      icon: icon,
                      label: Text(label),
                    )
                  : AsyncFilledButton(
                      busy: controller.busy,
                      onPressed: () =>
                          controller.makeSheet(controller.format.value),
                      icon: icon,
                      label: label,
                    ),
            ),
          ],
        );
      case StockSheetPhase.done:
        return _ActionBar(
          message: controller.errorMessage.value,
          children: [
            if (controller.files.isEmpty)
              Expanded(
                child: Text(
                  'Nothing to put on a sheet.',
                  style: TextStyle(color: context.scheme.textMuted),
                ),
              )
            else
              Expanded(
                child: AsyncFilledButton(
                  busy: controller.sharing,
                  onPressed: controller.shareAgain,
                  icon: const Icon(Icons.share_outlined),
                  label: controller.files.length == 1
                      ? 'Share file'
                      : 'Share files',
                ),
              ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _close, child: const Text('Done')),
          ],
        );
      case StockSheetPhase.error:
        return _ActionBar(
          children: [
            if (controller.canRetry)
              Expanded(
                child: AsyncFilledButton(
                  busy: controller.busy,
                  onPressed: controller.retry,
                  icon: const Icon(Icons.refresh),
                  label: 'Retry',
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _close, child: const Text('Done')),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// Asks what to do with [StockSheetController.pendingShare]. Add is offered
/// only when the photos fit under the limit.
class _PendingShareDialog extends StatelessWidget {
  const _PendingShareDialog({required this.controller});

  final StockSheetController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final n = controller.pendingShare.length;
      final fits = controller.pendingShareFits;
      const limit = StockSheetController.maxPhotos;
      final room = math.max(0, limit - controller.review.length);
      void answer(PendingShareChoice choice) =>
          Navigator.of(context).pop(choice);
      return AlertDialog(
        content: Text(
          fits
              ? n == 1
                    ? 'Add this photo to the list, or start again?'
                    : 'Add these $n photos to the list, or start again?'
              : 'Only $room more photos fit (limit $limit).',
        ),
        actions: [
          TextButton(
            onPressed: () => answer(PendingShareChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => answer(PendingShareChoice.startAgain),
            child: const Text('Start again'),
          ),
          if (fits)
            FilledButton(
              onPressed: () => answer(PendingShareChoice.add),
              child: const Text('Add'),
            ),
        ],
      );
    });
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label, this.value});

  final String label;

  /// Null for an indeterminate bar.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: value, backgroundColor: s.subtle),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(color: s.text)),
          ],
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: s.textSubtle),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: s.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom buttons, clear of the system navigation bar, with an optional
/// [top] control and error line above them.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children, this.message, this.top});

  final List<Widget> children;
  final String? message;
  final Widget? top;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = message;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.fg,
        border: Border(top: BorderSide(color: s.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (top != null) ...[top!, const SizedBox(height: 12)],
              if (text != null) ...[
                Text(
                  text,
                  style: TextStyle(
                    color: isDark ? AppColors.red300 : AppColors.red700,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(children: children),
            ],
          ),
        ),
      ),
    );
  }
}
