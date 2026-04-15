import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/dual_rack_delegate.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_source_rack_field.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_target_rack_field.dart';

/// Renders a source rack field followed by a target rack field.
///
/// The build() method no longer contains any SE-type string comparisons.
/// Visibility is declared by the controller: it overrides [showSourceRack]
/// and [showTargetRack] as needed (e.g. Manufacture FG row returns
/// showSourceRack = false).
class SharedDualRackSection extends StatelessWidget {
  final DualRackDelegate controller;
  const SharedDualRackSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Column(
      children: [
        if (controller.showSourceRack)
          SharedSourceRackField(controller: controller),
        if (controller.showTargetRack)
          SharedTargetRackField(controller: controller),
        // rack error banner
      ],
    ));
  }
}
