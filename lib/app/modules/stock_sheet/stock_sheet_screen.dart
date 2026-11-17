import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/stock_sheet/stock_sheet_controller.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/out_of_stock_sheet.dart';
import 'package:multimax/app/modules/stock_sheet/widgets/stock_sheet_result_list.dart';

/// Shared photos → stock sheet. Reads the photos on open, shows progress and
/// the review, asks about out-of-stock items when there are any, then shows
/// the result.
///
/// Stateful (not a GetView) because it drives the share and the out-of-stock
/// sheet from workers on the controller, which need this screen's lifetime
/// and context.
class StockSheetScreen extends StatefulWidget {
  const StockSheetScreen({super.key, this.paths});

  /// The shared photo paths; null takes them from the route arguments.
  final List<String>? paths;

  @override
  State<StockSheetScreen> createState() => _StockSheetScreenState();
}

class _StockSheetScreenState extends State<StockSheetScreen> {
  final StockSheetController controller = Get.find<StockSheetController>();
  final List<Worker> _workers = [];

  @override
  void initState() {
    super.initState();
    _workers
      ..add(ever<int>(controller.shareSerial, (_) => _startShare()))
      ..add(
        ever<StockSheetPhase>(controller.phase, (phase) {
          if (phase == StockSheetPhase.awaitingChoice) _askOutOfStock();
        }),
      );
    final paths = widget.paths ?? _argumentPaths();
    if (paths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.takeShare(paths);
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

  /// Closes any sheet open above this screen. Its pending answer is then
  /// ignored, because the share serial has moved on.
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

  Future<void> _startShare() async {
    if (!mounted) return;
    _closeSheetsAbove();
    // Over the photo limit, the controller refuses it with its message.
    await controller.start(controller.sharedPaths.toList());
  }

  Future<void> _askOutOfStock() async {
    if (!mounted) return;
    final serial = controller.shareSerial.value;
    final count = controller.result.value?.outOfStockCount ?? 0;
    final choice = await showOutOfStockSheet(context, count: count);
    if (!mounted || serial != controller.shareSerial.value) return;
    if (controller.phase.value != StockSheetPhase.awaitingChoice) return;
    // Dismissed (null), it goes back to the review.
    await controller.chooseOutOfStock(choice);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock sheet')),
      body: Obx(() {
        switch (controller.phase.value) {
          case StockSheetPhase.idle:
          case StockSheetPhase.awaitingChoice:
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
            return _ReviewPlaceholder(
              photos: controller.review.length,
              onSheet: controller.sheetPhotoCount,
            );
          case StockSheetPhase.building:
            return const _Progress(label: 'Building file…');
          case StockSheetPhase.done:
            final result = controller.result.value;
            if (result == null) return const SizedBox.shrink();
            return StockSheetResultList(
              result: result,
              photoCount: controller.total.value,
              thumbnails: Map.of(controller.thumbnails),
            );
          case StockSheetPhase.error:
            return _ErrorMessage(
              message: controller.errorMessage.value ?? 'Something went wrong.',
            );
        }
      }),
      bottomNavigationBar: Obx(() {
        switch (controller.phase.value) {
          case StockSheetPhase.reviewing:
            final n = controller.sheetPhotoCount;
            return _ActionBar(
              message: controller.errorMessage.value,
              children: [
                Expanded(
                  child: AsyncFilledButton(
                    busy: controller.busy,
                    onPressed: () =>
                        controller.makeSheet(controller.format.value),
                    icon: const Icon(Icons.description_outlined),
                    label: 'Make sheet · $n photo${n == 1 ? '' : 's'}',
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
      }),
    );
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

/// Stands in for the review list until it is built: the counts only.
class _ReviewPlaceholder extends StatelessWidget {
  const _ReviewPlaceholder({required this.photos, required this.onSheet});

  final int photos;
  final int onSheet;

  @override
  Widget build(BuildContext context) {
    final s = context.scheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Review photos',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: s.text),
          ),
          const SizedBox(height: 8),
          Text(
            '$photos photo${photos == 1 ? '' : 's'} · $onSheet on the sheet',
            style: TextStyle(color: s.textMuted),
          ),
        ],
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
/// error line above them.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children, this.message});

  final List<Widget> children;
  final String? message;

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
