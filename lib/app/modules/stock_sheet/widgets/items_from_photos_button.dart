import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/global_widgets/doctype_guard.dart';

/// Entry point to "Items from Photos" for the Item list and the Dashboard.
///
/// Opens the screen with no arguments, so it shows its start state. Gated on
/// the Stock Entry report permission, as the side menu gates Stock Balance.
class ItemsFromPhotosButton extends StatelessWidget {
  const ItemsFromPhotosButton({super.key, this.color});

  /// Icon colour; null keeps the ambient icon theme colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return DocTypeGuard(
      doctype: 'Stock Entry',
      permType: 'report',
      child: IconButton(
        icon: const Icon(Icons.photo_library_outlined),
        color: color,
        tooltip: 'Items from Photos',
        onPressed: () => Get.toNamed(AppRoutes.STOCK_SHEET),
      ),
    );
  }
}
