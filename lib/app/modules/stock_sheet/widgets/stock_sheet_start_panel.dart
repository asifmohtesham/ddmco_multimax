import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/app_theme.dart';

/// What "Items from photos" shows when it is opened without photos: the ways
/// to bring some in. A null [onTakePhoto] hides the camera (a Mac has none
/// worth offering) and the drag hint shows in its place.
class StockSheetStartPanel extends StatelessWidget {
  const StockSheetStartPanel({
    super.key,
    required this.onMac,
    required this.onChooseFiles,
    required this.onChooseGallery,
    this.onTakePhoto,
    this.busy = false,
  });

  final bool onMac;
  final VoidCallback onChooseFiles;
  final VoidCallback onChooseGallery;
  final VoidCallback? onTakePhoto;

  /// A picker is open: the buttons wait for it.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.photo_library_outlined,
                size: 48,
                color: context.scheme.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                'Choose photos of item labels to list their stock as '
                'Excel or PDF.',
                textAlign: TextAlign.center,
                style: text.bodyLarge?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: busy ? null : onChooseFiles,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Choose files…'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy ? null : onChooseGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose from gallery'),
              ),
              if (onTakePhoto != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy ? null : onTakePhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Take a photo'),
                ),
              ],
              if (onMac) ...[
                const SizedBox(height: 20),
                Text(
                  'On a Mac you can also drag photos here or share them '
                  'from Finder.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: context.scheme.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
