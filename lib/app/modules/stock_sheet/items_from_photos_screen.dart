import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/services/native_intake.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/stock_sheet/items_from_photos_controller.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/fix_code_sheet.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/item_image_viewer.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/out_of_stock_sheet.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/reading_strip.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/review_list.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/items_from_photos_result_list.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/items_from_photos_start_panel.dart';

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

/// The system file dialog (on a Mac it reaches OneDrive). On iOS the picker
/// copies the files into the app, so cloud placeholders arrive downloaded.
Future<List<String>> _chooseFiles() async {
  final files = await openFiles(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Images',
        extensions: ['jpg', 'jpeg', 'png', 'heic'],
        mimeTypes: ['image/*'],
        uniformTypeIdentifiers: ['public.image'],
      ),
    ],
  );
  return [for (final file in files) file.path];
}

Future<bool> _runningOnMac() => NativeIntake.instance.isRunningOnMac();

enum _AddSource { camera, gallery, files }

/// Shared photos → stock sheet. Reads the photos on open, shows progress,
/// then the review list (reorder, switch off, fix codes, add photos, pick
/// the format), asks about out-of-stock items when there are any, then shows
/// the result.
///
/// Stateful (not a GetView) because it drives the share, the out-of-stock
/// sheet and the new-share question from workers on the controller, which
/// need this screen's lifetime and context.
class ItemsFromPhotosScreen extends StatefulWidget {
  const ItemsFromPhotosScreen({
    super.key,
    this.paths,
    this.pickCamera = _takePhoto,
    this.pickGallery = _chooseFromGallery,
    this.pickFiles = _chooseFiles,
    this.runningOnMac = _runningOnMac,
  });

  /// The shared photo paths; null takes them from the route arguments.
  final List<String>? paths;

  /// ＋ → Take a photo.
  final PhotoPicker pickCamera;

  /// ＋ → Choose from gallery.
  final PhotoPicker pickGallery;

  /// Choose files… (start panel and ＋).
  final PhotoPicker pickFiles;

  /// Whether the iPhone/iPad app is running on a Mac (no camera, drag hint).
  final Future<bool> Function() runningOnMac;

  @override
  State<ItemsFromPhotosScreen> createState() => _ItemsFromPhotosScreenState();
}

class _ItemsFromPhotosScreenState extends State<ItemsFromPhotosScreen> {
  final ItemsFromPhotosController controller = Get.find<ItemsFromPhotosController>();
  final List<Worker> _workers = [];

  /// Bumped when this screen closes the sheets above it for a new share, so
  /// the out-of-stock sheet's late (null) answer is ignored.
  int _sheetEpoch = 0;

  bool _askingPending = false;
  bool _askingDiscard = false;

  /// Opened with no photos, so the start panel shows while idle.
  bool _openedEmpty = false;

  bool _onMac = false;

  /// A picker is open; a second one is not started.
  final RxBool _picking = false.obs;

  @override
  void initState() {
    super.initState();
    widget.runningOnMac().then<void>((onMac) {
      if (mounted && onMac != _onMac) setState(() => _onMac = onMac);
    }, onError: (Object _) {});
    _workers
      ..add(ever<int>(controller.shareSerial, (_) => _startShare()))
      ..add(
        ever<ItemsFromPhotosPhase>(controller.phase, (phase) {
          if (phase != ItemsFromPhotosPhase.reviewing) _closeUndoBar();
          if (phase == ItemsFromPhotosPhase.awaitingChoice) _askOutOfStock();
        }),
      )
      ..add(
        ever<int>(
          controller.alreadyListed,
          (_) => AppNotification.warning(
            ItemsFromPhotosController.alreadyListedMessage,
          ),
        ),
      )
      ..add(
        ever<List<String>>(controller.pendingShare, (paths) {
          if (paths.isNotEmpty) _askPendingShare();
        }),
      );
    final paths = widget.paths ?? _argumentPaths();
    _openedEmpty = paths.isEmpty;
    if (paths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.offerShare(paths);
      });
    }
  }

  @override
  void dispose() {
    _closeUndoBar();
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
    ItemsFromPhotosPhase.reviewing || ItemsFromPhotosPhase.awaitingChoice => true,
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
    if (controller.phase.value != ItemsFromPhotosPhase.awaitingChoice) return;
    // Dismissed (null), it goes back to the review.
    await controller.chooseOutOfStock(choice);
  }

  /// A share arrived during the review: add it, start again, or drop it.
  /// The question shows over whatever is open; Add and Start again close
  /// that first, so its answer cannot act on the new state. An Add that no
  /// longer fits once an add in flight lands is held again, and this asks
  /// again.
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
    final error = await controller.resolvePendingShare(choice);
    if (mounted && error != null) AppNotification.warning(error);
  }

  /// Back during the review, or while the photos given are fingerprinted:
  /// the photos go only if the user says so. The controller's onClose
  /// cleans up once the screen has gone.
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

  /// The row is named by its id, taken now: while the code is typed, rows
  /// above it can become several, so its index may change.
  void _fix(int index) {
    if (index < 0 || index >= controller.review.length) return;
    final rowId = controller.review[index].id;
    showFixCodeSheet(
      context,
      onSubmit: (code) => controller.fixCode(rowId, code),
    );
  }

  /// Takes the swiped row off the list and offers to put it back.
  /// Returns whether the row was removed.
  bool _remove(int index) {
    final entry = controller.removeAt(index);
    if (entry == null) return false;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    // A snackbar with an action persists by default; this one must not.
    _undoBar = messenger.showSnackBar(
      SnackBar(
        persist: false,
        duration: const Duration(seconds: 5),
        content: Text(entry.resolved ? 'Item removed.' : 'Photo removed.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => controller.restore(entry, index),
        ),
      ),
    );
    return true;
  }

  /// The "Item removed." / "Photo removed." snackbar, while it is showing.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _undoBar;

  void _closeUndoBar() {
    final bar = _undoBar;
    _undoBar = null;
    try {
      bar?.close();
    } catch (_) {
      // The messenger has gone with the screen.
    }
  }

  /// "Retry check" on any row checks every "Stock not checked" row.
  Future<void> _retryCheck(int _) async {
    final error = await controller.retryCheck();
    if (mounted && error != null) AppNotification.warning(error);
  }

  /// Runs the picker for [source]; null when it failed (said in a warning),
  /// empty when cancelled, or when one is already open.
  Future<List<String>?> _pick(_AddSource source) async {
    if (_picking.value) return null;
    _picking.value = true;
    try {
      return await switch (source) {
        _AddSource.camera => widget.pickCamera(),
        _AddSource.gallery => widget.pickGallery(),
        _AddSource.files => widget.pickFiles(),
      };
    } catch (e, st) {
      if (kDebugMode) debugPrint('StockSheetScreen: pick failed: $e\n$st');
      AppNotification.warning(switch (source) {
        _AddSource.camera => "Couldn't open the camera.",
        _AddSource.gallery => "Couldn't open the gallery.",
        _AddSource.files => "Couldn't open the file dialog.",
      });
      return null;
    } finally {
      _picking.value = false;
    }
  }

  Future<void> _add(_AddSource source) async {
    if (controller.adding.value) return;
    final paths = await _pick(source);
    if (!mounted || paths == null || paths.isEmpty) return;
    final error = await controller.addPhotos(paths);
    if (mounted && error != null) AppNotification.warning(error);
  }

  /// From the start panel: the picked photos start a run as a share would.
  Future<void> _startFrom(_AddSource source) async {
    final paths = await _pick(source);
    if (!mounted || paths == null || paths.isEmpty) return;
    controller.offerShare(paths);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final reviewing = _reviewing;
      // From the first frame with photos: while they are fingerprinted too.
      final askFirst =
          reviewing || controller.phase.value == ItemsFromPhotosPhase.decoding;
      return PopScope(
        canPop: !askFirst,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmDiscard();
        },
        child: Scaffold(
          appBar: reviewing
              ? _reviewAppBar()
              : AppBar(title: const Text('Items from Photos')),
          body: Obx(_body),
          bottomNavigationBar: Obx(_footer),
        ),
      );
    });
  }

  PreferredSizeWidget _reviewAppBar() {
    return AppBar(
      title: Obx(() {
        final photos = controller.photoCount;
        final items = controller.sheetItemCount;
        final reading = controller.reading.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Review photos'),
            Text(
              '$photos photo${photos == 1 ? '' : 's'} · '
              '$items item${items == 1 ? '' : 's'} '
              '${reading ? 'so far' : 'in the file'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        );
      }),
      actions: [
        // Its own Obx, so the icon → spinner swap repaints while adding.
        Obx(() {
          final adding = controller.adding.value;
          // This context is above the AppBar, so the AppBar's foreground
          // is named here: the spinner sits on the maroon bar.
          final onBar =
              Theme.of(context).appBarTheme.foregroundColor ??
              Theme.of(context).colorScheme.onPrimary;
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
                      color: onBar,
                    ),
                  )
                : const Icon(Icons.add),
            itemBuilder: (_) => [
              if (!_onMac)
                const PopupMenuItem(
                  value: _AddSource.camera,
                  child: ListTile(
                    leading: Icon(Icons.photo_camera_outlined),
                    title: Text('Take a photo'),
                  ),
                ),
              const PopupMenuItem(
                value: _AddSource.gallery,
                child: ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('Choose from gallery'),
                ),
              ),
              const PopupMenuItem(
                value: _AddSource.files,
                child: ListTile(
                  leading: Icon(Icons.folder_open_outlined),
                  title: Text('Choose files…'),
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
      case ItemsFromPhotosPhase.idle:
        if (!_openedEmpty) return const SizedBox.shrink();
        return Obx(
          () => ItemsFromPhotosStartPanel(
            onMac: _onMac,
            busy: _picking.value,
            onChooseFiles: () => _startFrom(_AddSource.files),
            onChooseGallery: () => _startFrom(_AddSource.gallery),
            onTakePhoto: _onMac ? null : () => _startFrom(_AddSource.camera),
          ),
        );
      case ItemsFromPhotosPhase.decoding:
        // Only the moment the photos are fingerprinted; the reading itself
        // shows in the review's strip.
        return _Progress(
          label: 'Reading photo 1 of ${controller.total.value}',
        );
      case ItemsFromPhotosPhase.reviewing:
      case ItemsFromPhotosPhase.awaitingChoice:
        // The list stays behind the out-of-stock question.
        return Column(
          children: [
            // Built from the same rows as the list: the body's Obx rebuilds
            // both whenever a row changes.
            ReadingStrip(entries: controller.review.toList()),
            Expanded(child: _reviewList()),
          ],
        );
      case ItemsFromPhotosPhase.building:
        return const _Progress(label: 'Generating the file…');
      case ItemsFromPhotosPhase.done:
        final result = controller.result.value;
        if (result == null) return const SizedBox.shrink();
        return ItemsFromPhotosResultList(
          result: result,
          // The photos on the sheet, as in the file's subtitle.
          photoCount: controller.sheetPhotoCount,
          thumbnails: Map.of(controller.thumbnails),
        );
      case ItemsFromPhotosPhase.error:
        return _ErrorMessage(
          message: controller.errorMessage.value ?? 'Something went wrong.',
        );
    }
  }

  Widget _reviewList() {
    return ReviewList(
      entries: controller.review.toList(),
      thumbnails: Map.of(controller.thumbnails),
      onReorder: controller.reorder,
      onToggle: controller.setIncluded,
      onFix: _fix,
      onRetryCheck: _retryCheck,
      onRemove: _remove,
      removeEnabled: controller.canRemove,
      recheckBusy: controller.rechecking,
      openCards: controller.openCards.toSet(),
      ageing: Map.of(controller.ageing),
      onToggleCard: controller.toggleCard,
      onRetryAgeing: controller.retryAgeing,
      onPreviewImage: (context, info) {
        final url = info.image!.trim();
        final sheet = controller;
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ItemImageViewer(
              item: info,
              cachedBytes: sheet.cachedItemImage(url),
              load: ({required refresh}) =>
                  sheet.itemImage(url, refresh: refresh),
            ),
          ),
        );
      },
    );
  }

  /// Saves the files to a folder the user picks. Outlined beside the filled
  /// Share files; icon-only on a narrow screen so the row fits at 360 dp.
  Widget _downloadButton(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 400;
    return Obx(() {
      final busy = controller.downloading.value;
      final icon = busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.download_outlined);
      final VoidCallback? onPressed = busy ? null : _download;
      if (compact) {
        return Tooltip(
          message: 'Download',
          child: OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.zero,
            ),
            child: icon,
          ),
        );
      }
      return OutlinedButton.icon(
        onPressed: onPressed,
        icon: icon,
        label: const Text('Download'),
      );
    });
  }

  Future<void> _download() async {
    final message = await controller.download();
    if (!mounted || message == null) return;
    if (message == ItemsFromPhotosController.saveFailedMessage) {
      AppNotification.warning(message);
    } else {
      AppNotification.success(message);
    }
  }

  Widget _footer() {
    switch (controller.phase.value) {
      case ItemsFromPhotosPhase.reviewing:
      case ItemsFromPhotosPhase.awaitingChoice:
        // One row of the file per item switched on.
        final n = controller.sheetItemCount;
        final label = 'Generate file · $n item${n == 1 ? '' : 's'}';
        const icon = Icon(Icons.description_outlined);
        // Nothing on the sheet, or the list still changing (photos being read
        // included): makeSheet would refuse, so the button says so by being
        // disabled.
        final blocked =
            n == 0 ||
            controller.reading.value ||
            controller.adding.value ||
            controller.rechecking.value ||
            controller.fixing.value;
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
      case ItemsFromPhotosPhase.done:
        return _ActionBar(
          message: controller.errorMessage.value,
          children: [
            if (controller.files.isEmpty)
              Expanded(
                child: Text(
                  'Nothing to put in a file.',
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
            if (controller.files.isNotEmpty) ...[
              const SizedBox(width: 12),
              _downloadButton(context),
            ],
            const SizedBox(width: 12),
            OutlinedButton(onPressed: _close, child: const Text('Done')),
          ],
        );
      case ItemsFromPhotosPhase.error:
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

/// Asks what to do with [ItemsFromPhotosController.pendingShare]. Add is offered
/// only when the photos fit under the limit, counting photos still being
/// added. The text follows a second share joining the first and an add
/// landing; once the share is cleared on answering, the last text stays
/// while the dialog fades out.
class _PendingShareDialog extends StatefulWidget {
  const _PendingShareDialog({required this.controller});

  final ItemsFromPhotosController controller;

  @override
  State<_PendingShareDialog> createState() => _PendingShareDialogState();
}

class _PendingShareDialogState extends State<_PendingShareDialog> {
  ({int count, bool fits, int room})? _asked;

  void _answer(PendingShareChoice choice) => Navigator.of(context).pop(choice);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final c = widget.controller;
      final count = c.pendingShare.length;
      if (count > 0) {
        _asked = (count: count, fits: c.pendingShareFits, room: c.photoRoom);
      }
      final asked = _asked ?? (count: 0, fits: false, room: 0);
      return AlertDialog(
        content: Text(
          asked.fits
              ? asked.count == 1
                    ? 'Add this photo to the list, or start again?'
                    : 'Add these ${asked.count} photos to the list, or start again?'
              : ItemsFromPhotosController.roomMessage(asked.room),
        ),
        actions: [
          TextButton(
            onPressed: () => _answer(PendingShareChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => _answer(PendingShareChoice.startAgain),
            child: const Text('Start again'),
          ),
          if (asked.fits)
            FilledButton(
              onPressed: () => _answer(PendingShareChoice.add),
              child: const Text('Add'),
            ),
        ],
      );
    });
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(backgroundColor: s.subtle),
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
