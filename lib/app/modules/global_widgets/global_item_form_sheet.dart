import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';

class GlobalItemFormSheet extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final ScrollController? scrollController;
  final String title;
  final String itemCode;
  final String itemName;
  final String? itemSubtext;
  final List<Widget> customFields;
  final TextEditingController qtyController;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final String? qtyInfoText;
  final bool isQtyReadOnly;
  final Function onSubmit;
  final VoidCallback? onDelete;
  final bool isSaveEnabled;
  final RxBool? isSaveEnabledRx;
  final bool isSaving;
  final bool isLoading;
  final String? owner;
  final String? creation;
  final String? modified;
  final String? modifiedBy;
  final Function(String)? onScan;
  final TextEditingController? scanController;
  final bool isScanning;

  const GlobalItemFormSheet({
    super.key,
    required this.formKey,
    required this.scrollController,
    required this.title,
    required this.itemCode,
    required this.itemName,
    this.itemSubtext,
    this.customFields = const [],
    required this.qtyController,
    required this.onIncrement,
    required this.onDecrement,
    this.qtyInfoText,
    this.isQtyReadOnly = false,
    required this.onSubmit,
    this.onDelete,
    this.isSaveEnabled = true,
    this.isSaveEnabledRx,
    this.isSaving = false,
    this.isLoading = false,
    this.owner,
    this.creation,
    this.modified,
    this.modifiedBy,
    this.onScan,
    this.scanController,
    this.isScanning = false,
  });

  /// Restored Static Helper for Compatibility
  /// Used by: PurchaseReceipt, DeliveryNote, PurchaseOrder forms
  static Widget buildInputGroup({
    required String label,
    required Color color,
    required Widget child,
    Color? bgColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: bgColor ?? color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.viewPadding.bottom;
    final viewInsetsBottom = mediaQuery.viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(top: mediaQuery.viewPadding.top + 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // 1. Drag Handle
          const _DragHandle(),

          // 2. Actions Header (Delete Left / Save Right)
          _FormActionBar(
            title: title,
            onDelete: onDelete,
            onSubmit: onSubmit,
            formKey: formKey,
            isSaveEnabled: isSaveEnabled,
            isSaveEnabledRx: isSaveEnabledRx,
            isSaving: isSaving,
            isLoading: isLoading,
          ),

          const Divider(height: 1),

          // 3. Scrollable Content
          Expanded(
            child: Form(
              key: formKey,
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                shrinkWrap: true,
                children: [
                  // Item Details (Code & Name)
                  _ItemIdentityHeader(
                    itemCode: itemCode,
                    itemName: itemName,
                    itemSubtext: itemSubtext,
                  ),

                  const SizedBox(height: 24),

                  // Dynamic Fields
                  ...customFields.map((w) => Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: w,
                  )),

                  // Quantity Input
                  QuantityInputWidget(
                    controller: qtyController,
                    onIncrement: onIncrement,
                    onDecrement: onDecrement,
                    isReadOnly: isQtyReadOnly,
                    label: 'Quantity',
                    infoText: qtyInfoText,
                  ),

                  // Metadata
                  _MetadataSection(
                    owner: owner,
                    creation: creation,
                    modified: modified,
                    modifiedBy: modifiedBy,
                  ),

                  SizedBox(height: math.max(viewInsetsBottom, bottomPadding) + 20),
                ],
              ),
            ),
          ),

          // 4. Sticky Scanner
          if (onScan != null)
            _ScannerFooter(
              onScan: onScan!,
              scanController: scanController,
              isScanning: isScanning,
              bottomPadding: bottomPadding,
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SUB-WIDGETS
// -----------------------------------------------------------------------------

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      alignment: Alignment.center,
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _FormActionBar extends StatelessWidget {
  final String title;
  final VoidCallback? onDelete;
  final Function onSubmit;
  final GlobalKey<FormState> formKey;
  final bool isSaveEnabled;
  final RxBool? isSaveEnabledRx;
  final bool isSaving;
  final bool isLoading;

  final RxBool _isInternalLoading = false.obs;

  _FormActionBar({
    required this.title,
    this.onDelete,
    required this.onSubmit,
    required this.formKey,
    required this.isSaveEnabled,
    this.isSaveEnabledRx,
    required this.isSaving,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          // Left: Delete Button (if applicable)
          if (onDelete != null)
            IconButton(
              onPressed: () {
                Get.back(); // Close sheet logic
                onDelete!();
              },
              icon: const Icon(Icons.delete_outline),
              color: theme.colorScheme.error,
              tooltip: 'Delete Item',
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
              ),
            )
          else
            const SizedBox(width: 48), // Placeholder for alignment if needed

          // Center: Title
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // Right: Save Button
          SizedBox(
            width: onDelete != null ? null : 80, // Balance width if delete is missing
            child: Align(
              alignment: Alignment.centerRight,
              child: isSaveEnabledRx != null
                  ? Obx(() => _buildSaveButton(context, isSaveEnabledRx!.value))
                  : _buildSaveButton(context, isSaveEnabled),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(BuildContext context, bool enabled) {
    return Obx(() {
      final showLoading = isSaving || isLoading || _isInternalLoading.value;
      final canPress = enabled && !showLoading;

      return FilledButton(
        onPressed: canPress ? () => _handlePress(context) : null,
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: showLoading
            ? SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.onPrimary,
            strokeWidth: 2,
          ),
        )
            : const Text('Save'),
      );
    });
  }

  Future<void> _handlePress(BuildContext context) async {
    if (formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      _isInternalLoading.value = true;
      await Future.delayed(const Duration(milliseconds: 300));

      try {
        var result = onSubmit();
        if (result is Future) await result;
        Get.back();
      } catch (e) {
        debugPrint('Form Error: $e');
      } finally {
        _isInternalLoading.value = false;
      }
    }
  }
}

class _ItemIdentityHeader extends StatelessWidget {
  final String itemCode;
  final String itemName;
  final String? itemSubtext;

  const _ItemIdentityHeader({
    required this.itemCode,
    required this.itemName,
    this.itemSubtext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Item Code Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Text(
            '$itemCode${itemSubtext != null && itemSubtext!.isNotEmpty ? ' • $itemSubtext' : ''}',
            style: theme.textTheme.labelMedium?.copyWith(
              fontFamily: 'ShureTechMono',
              letterSpacing: 0.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Item Name
        Text(
          itemName,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
            height: 1.2,
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MetadataSection extends StatelessWidget {
  final String? owner;
  final String? creation;
  final String? modified;
  final String? modifiedBy;

  const _MetadataSection({this.owner, this.creation, this.modified, this.modifiedBy});

  @override
  Widget build(BuildContext context) {
    if (owner == null && creation == null && modified == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final variantColor = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelSmall?.copyWith(color: variantColor);

    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetaRow(Icons.person_outline, owner, creation, style, variantColor),
          if ((modified != null || modifiedBy != null) && (modified != creation)) ...[
            const SizedBox(height: 6),
            _buildMetaRow(Icons.edit_outlined, modifiedBy, modified, style, variantColor),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaRow(IconData icon, String? name, String? date, TextStyle? style, Color iconColor) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        if (name != null) ...[
          Text(name, style: style?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text('•', style: style),
          const SizedBox(width: 6),
        ],
        if (date != null) Text(FormattingHelper.getRelativeTime(date), style: style),
      ],
    );
  }
}

class _ScannerFooter extends StatelessWidget {
  final Function(String) onScan;
  final TextEditingController? scanController;
  final bool isScanning;
  final double bottomPadding;

  const _ScannerFooter({
    required this.onScan,
    this.scanController,
    required this.isScanning,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, -4),
          )
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
      child: BarcodeInputWidget(
        onScan: onScan,
        controller: scanController,
        isLoading: isScanning,
        hintText: 'Scan Rack / Batch / Item',
        isEmbedded: true,
      ),
    );
  }
}