import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Provides a managed [ScrollController] with load-more pagination and a
/// reactive scroll-position flag for FAB visibility.
///
/// Mix into any [GetxController] that drives a paginated list screen.
/// Call [initScrollListener] from [onClose] is handled automatically —
/// callers must **not** call `scrollController.dispose()` themselves.
///
/// ## Usage
///
/// ```dart
/// class BatchController extends GetxController with ListScrollMixin {
///   final hasMore = true.obs;
///   final isFetchingMore = false.obs;
///
///   @override
///   void onInit() {
///     super.onInit();
///     initScrollListener(
///       onLoadMore: () => fetchBatches(isLoadMore: true),
///       hasMore: hasMore,
///       isFetchingMore: isFetchingMore,
///     );
///   }
/// }
/// ```
///
/// ## View binding
///
/// ```dart
/// Obx(() => FloatingActionButton.extended(
///   // Collapses to icon-only when user has scrolled down
///   label: controller.isFarFromTop.value
///       ? const SizedBox.shrink()
///       : const Text('New Batch'),
///   icon: const Icon(Icons.add),
///   onPressed: controller.navigateToCreate,
/// ));
/// ```
mixin ListScrollMixin on GetxController {
  /// The scroll controller to attach to the list view in the screen.
  ///
  /// Do **not** call [ScrollController.dispose] from the view — [onClose]
  /// handles disposal automatically.
  final scrollController = ScrollController();

  /// `true` once the user scrolls more than 80 px from the top.
  ///
  /// Bind to a FAB's extended/collapsed state in the view so the FAB
  /// shrinks out of the way when the user is reading mid-list.
  final isFarFromTop = false.obs;

  VoidCallback? _loadMoreCallback;
  RxBool? _hasMore;
  RxBool? _isFetchingMore;

  /// Attaches the scroll listener.
  ///
  /// Must be called once from [GetxController.onInit].
  ///
  /// - [onLoadMore]      : callback invoked when the list nears its bottom end.
  /// - [hasMore]         : reactive flag — load-more is skipped when `false`.
  /// - [isFetchingMore]  : reactive flag — prevents concurrent load-more calls.
  void initScrollListener({
    required VoidCallback onLoadMore,
    required RxBool hasMore,
    required RxBool isFetchingMore,
  }) {
    _loadMoreCallback = onLoadMore;
    _hasMore = hasMore;
    _isFetchingMore = isFetchingMore;
    scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!scrollController.hasClients) return;

    final offset = scrollController.offset;
    final maxExtent = scrollController.position.maxScrollExtent;

    // ── Load-more trigger at 90 % scroll depth ──────────────────────────────
    if (maxExtent > 0 &&
        offset >= maxExtent * 0.9 &&
        (_hasMore?.value ?? false) &&
        !(_isFetchingMore?.value ?? false)) {
      _loadMoreCallback?.call();
    }

    // ── FAB collapse flag ───────────────────────────────────────────────────
    final far = offset > 80;
    if (isFarFromTop.value != far) isFarFromTop.value = far;
  }

  @override
  void onClose() {
    scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.onClose();
  }
}
