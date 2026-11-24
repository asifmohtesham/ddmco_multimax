import 'package:flutter/widgets.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

class SupplierStatusPill extends StatelessWidget {
  const SupplierStatusPill({super.key, required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final label = status;
    if (label == null || label == 'Active') return const SizedBox.shrink();

    final colorStatus = switch (label) {
      'Disabled' => 'Cancelled',
      String status when status.startsWith('On Hold ') => 'On Hold',
      _ => label,
    };
    return StatusPill(status: label, colorStatus: colorStatus);
  }
}
