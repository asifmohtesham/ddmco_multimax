import 'package:flutter/material.dart';
import 'package:get/get.dart';

class RealtimeSyncStatusIcon extends StatelessWidget {
  final RxBool isConnected;
  final RxBool isSyncing;

  const RealtimeSyncStatusIcon({
    super.key,
    required this.isConnected,
    required this.isSyncing,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (isSyncing.value) {
        return const SizedBox(
          width: 40,
          height: 40,
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
        );
      }
      if (!isConnected.value) {
        return IconButton(
          icon: const Icon(Icons.cloud_off_outlined, size: 18),
          color: Colors.orange,
          tooltip: 'Live sync inactive — conflict protection off',
          onPressed: null,
        );
      }
      return const SizedBox.shrink();
    });
  }
}
