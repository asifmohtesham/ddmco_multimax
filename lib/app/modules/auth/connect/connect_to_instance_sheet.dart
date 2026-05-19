import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:multimax/app/core/widgets/keyboard_safe_bottom_sheet.dart';
import 'package:multimax/app/modules/auth/connect/connect_to_instance_controller.dart';
import 'package:multimax/app/modules/auth/connect/qr_scan_sheet.dart';

class ConnectToInstanceSheet extends GetView<ConnectToInstanceController> {
  const ConnectToInstanceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ConnectToInstanceController>(
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connect to Instance',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the URL of your ERP instance.',
            style: TextStyle(color: Colors.grey),
          ),
          if (c.currentServerUrl.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Current: ${c.currentServerUrl}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: c.serverUrlController,
            decoration: InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://erp.domain.com',
              prefixIcon: const Icon(Icons.link),
              border: const OutlineInputBorder(),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.content_paste),
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data =
                          await Clipboard.getData(Clipboard.kTextPlain);
                      final text = data?.text?.trim();
                      if (text != null && text.isNotEmpty) {
                        c.fillUrl(text);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Scan QR code',
                    onPressed: () =>
                        showQRScanSheet(context, onUrlScanned: c.fillUrl),
                  ),
                ],
              ),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            autofocus: true,
            autocorrect: false,
            onSubmitted: (_) => c.saveServerConfiguration(),
          ),
          if (c.recentUrls.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'RECENT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            ...c.recentUrls.take(5).map(
                  (url) => _RecentUrlTile(
                    url: url,
                    onTap: () => c.fillUrl(url),
                    onDelete: () => c.removeRecentUrl(url),
                  ),
                ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: c.isCheckingConnection.value
                  ? null
                  : c.saveServerConfiguration,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: c.isCheckingConnection.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentUrlTile extends StatelessWidget {
  const _RecentUrlTile({
    required this.url,
    required this.onTap,
    required this.onDelete,
  });

  final String url;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(6),
            color: Colors.grey.shade50,
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    url,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                onPressed: onDelete,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the Connect to Instance sheet.
/// Caller is responsible for registering [ConnectToInstanceController] via
/// `Get.put` before calling this and deleting it after the returned Future
/// completes.
Future<void> showConnectToInstanceSheet(BuildContext context) {
  return showKeyboardSafeBottomSheet(
    context: context,
    child: const ConnectToInstanceSheet(),
  );
}
