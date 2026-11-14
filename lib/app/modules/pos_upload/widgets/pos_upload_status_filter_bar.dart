import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/global_widgets/selectable_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/pos_upload/pos_upload_controller.dart';

/// One-tap status facet rendered above the POS Upload list: an 'All' chip
/// plus one chip per [PosUpload.statusOptions] entry, each carrying its
/// status-ramp dot so the row reads at a glance. Tapping a status applies
/// it as the list's status filter, tapping it again (or 'All') clears it;
/// other active filters are preserved. Stays in sync with the filter
/// bottom sheet and card-pill taps because all three write through the
/// controller's `activeFilters['status']`.
class PosUploadStatusFilterBar extends StatelessWidget {
  const PosUploadStatusFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final PosUploadController controller = Get.find();
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: SizedBox(
        height: 36,
        child: Obx(() {
          final active = controller.activeFilters['status'] as String?;
          final items = <String?>[null, ...PosUpload.statusOptions];
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final status = items[i];
              return Align(
                alignment: Alignment.center,
                child: status == null
                    ? SelectableFilterChip(
                        label: 'All',
                        selected: active == null,
                        onSelected: (_) {
                          if (active != null) controller.removeFilter('status');
                        },
                      )
                    : SelectableFilterChip(
                        label: status,
                        dotColor: StatusPill.dotColorForStatus(status),
                        selected: active == status,
                        onSelected: (_) =>
                            controller.toggleStatusFilter(status),
                      ),
              );
            },
          );
        }),
      ),
    );
  }
}
