import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/batch/batch_controller.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';

/// DocTypeListAppBar for the **Batch** DocType.
///
/// Wraps [DocTypeListHeader] and pre-wires [BatchController] reactive state
/// so [BatchScreen] only needs a single sliver entry:
///
/// ```dart
/// CustomScrollView(
///   slivers: [
///     const BatchListAppBar(),
///     // … list content slivers …
///   ],
/// )
/// ```
///
/// ### What this widget owns
/// | Concern | Wired to |
/// |---|---|
/// | Collapsing large title | `'Batch'` (static) |
/// | Global ERPNext search | `Batch` doctype → [AppRoutes.BATCH_FORM] |
/// | Local SearchBar | `controller.searchQuery` + `controller.onSearchChanged` |
/// | Clear search button | Clears query and triggers `fetchBatches(clear: true)` |
///
/// Batch has no filter sheet yet, so [activeFilters] and
/// [filterChipsBuilder] are intentionally omitted — the filter badge
/// will not appear until a `BatchFilterBottomSheet` is added.
class BatchListAppBar extends StatelessWidget {
  const BatchListAppBar({super.key});

  @override
  Widget build(BuildContext context) {
    final BatchController controller = Get.find();

    return DocTypeListHeader(
      title: 'Batch',

      // Global ERPNext API search ──────────────────────────────────────────
      searchDoctype: 'Batch',
      searchRoute: AppRoutes.BATCH_FORM,

      // Local SearchBar ────────────────────────────────────────────────────
      searchQuery: controller.searchQuery,
      searchHint: 'Filter batches by name…',
      onSearchChanged: controller.onSearchChanged,
      onSearchClear: () {
        controller.searchQuery.value = '';
        controller.fetchBatches(clear: true);
      },

      // No filter sheet / chips for Batch yet ───────────────────────────
      // onFilterTap and filterChipsBuilder are intentionally null.
    );
  }
}
