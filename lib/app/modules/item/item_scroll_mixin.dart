import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Scroll-state mixin for [ItemController].
///
/// Owns the [ScrollController] lifecycle and two reactive flags:
/// - [isFarFromTop]: drives the scroll-to-top FAB visibility.
///
/// Load-more is triggered when the scroll position reaches
/// 90 % of the max extent — matching the StockEntry screen threshold.
///
/// Call [initScroll] from [GetxController.onInit], passing the callback
/// that should fire when the user scrolls near the bottom.
/// Disposal is handled automatically in [onClose].
mixin ItemScrollMixin on GetxController {
  final scrollController = ScrollController();
  final isFarFromTop = false.obs;

  // Prevents concurrent load-more calls triggered by rapid scroll events.
  bool _loadMoreScheduled = false;

  /// Wire up the scroll listener. Call once from [onInit].
  void initScroll(VoidCallback onLoadMore) {
    scrollController.addListener(() {
      _handleLoadMore(onLoadMore);
      _handleFarFromTop();
    });
  }

  void _handleLoadMore(VoidCallback onLoadMore) {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent * 0.9 &&
        !_loadMoreScheduled) {
      _loadMoreScheduled = true;
      // Reset the gate after the frame so rapid scroll events
      // cannot queue multiple fetches.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadMoreScheduled = false;
      });
      onLoadMore();
    }
  }

  void _handleFarFromTop() {
    if (!scrollController.hasClients) return;
    isFarFromTop.value = scrollController.offset > 300;
  }

  /// Animate back to the top of the list.
  void scrollToTop() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}
