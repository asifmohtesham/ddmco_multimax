import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/modules/global_widgets/item_form_sheet_controller.dart';
import 'package:multimax/app/modules/global_widgets/quantity_input_widget.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/shared/item_sheet/item_sheet_controller_base.dart';

// ---------------------------------------------------------------------------
// _AnimatedSaveButton
// ---------------------------------------------------------------------------
class _AnimatedSaveButton extends StatelessWidget {
  final Rx<SaveButtonState> saveButtonState;
  final bool isSaveEnabled;
  final RxBool? isSaveEnabledRx;
  final bool isLoading;
  final String title;
  final Future<void> Function() onSubmit;
  final GlobalKey<FormState> formKey;
  final String sheetTag;

  const _AnimatedSaveButton({
    required this.saveButtonState,
    required this.isSaveEnabled,
    this.isSaveEnabledRx,
    required this.isLoading,
    required this.title,
    required this.onSubmit,
    required this.formKey,
    required this.sheetTag,
  });

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final state     = saveButtonState.value;
      final rxEnabled = isSaveEnabledRx?.value ?? true;
      final canTap    = isSaveEnabled &&
                        rxEnabled &&
                        !isLoading &&
                        state == SaveButtonState.idle;

      final Color bgColor;
      switch (state) {
        case SaveButtonState.loading:
          bgColor = Colors.orange.shade700;
        case SaveButtonState.success:
          bgColor = Colors.green.shade600;
        case SaveButtonState.error:
          bgColor = Colors.red.shade600;
        case SaveButtonState.idle:
          bgColor = canTap
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest;
      }

      final Widget child;
      switch (state) {
        case SaveButtonState.loading:
          child = const SizedBox(
            key: ValueKey('loading'),
            width: 22, height: 22,
            child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2.5),
          );
        case SaveButtonState.success:
          child = const Icon(
            key: ValueKey('success'),
            Icons.check_circle_outline, color: Colors.white, size: 24);
        case SaveButtonState.error:
          child = const Icon(
            key: ValueKey('error'),
            Icons.error_outline, color: Colors.white, size: 24);
        case SaveButtonState.idle:
          child = Row(
            key: const ValueKey('idle'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.save_outlined,
                color: canTap
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: canTap
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
      }

      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: canTap
                ? () async {
                    if (formKey.currentState!.validate()) {
                      FocusScope.of(context).unfocus();
                      await onSubmit();
                    }
                  }
                : null,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: child,
              ),
            ),
          ),
        ),
      );
    });
  }
}

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

  /// Optional breakdown string shown in a dialog when the Max badge is tapped.
  /// When null the badge is non-interactive (no info icon rendered).
  final String? qtyInfoTooltip;

  final bool isQtyReadOnly;

  final Function onSubmit;
  final VoidCallback? onDelete;

  final bool isSaveEnabled;
  final RxBool? isSaveEnabledRx;
  final bool isLoading;
  final Rx<SaveButtonState> saveButtonState;

  final String? owner;
  final String? creation;
  final String? modified;
  final String? modifiedBy;

  final Function(String)? onScan;
  final TextEditingController? scanController;
  final bool isScanning;

  late final String _sheetTag;

  GlobalItemFormSheet({
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
    this.qtyInfoTooltip,
    this.isQtyReadOnly = false,
    required this.onSubmit,
    this.onDelete,
    this.isSaveEnabled = true,
    this.isSaveEnabledRx,
    this.isLoading = false,
    Rx<SaveButtonState>? saveButtonState,
    this.owner,
    this.creation,
    this.modified,
    this.modifiedBy,
    this.onScan,
    this.scanController,
    this.isScanning = false,
  }) : saveButtonState = saveButtonState ?? SaveButtonState.idle.obs {
    _sheetTag = key != null
        ? key.toString()
        : 'sheet_${DateTime.now().microsecondsSinceEpoch}';
  }

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

  ItemFormSheetController get _sheetCtrl =>
      Get.put(ItemFormSheetController(), tag: _sheetTag, permanent: false);

  static void _popSheet(BuildContext context) =>
      Navigator.of(context).pop();

  Widget _buildMetadataHeader(BuildContext context) {
    if (owner == null &&
        creation == null &&
        modified == null &&
        modifiedBy == null) return const SizedBox.shrink();

    final theme        = Theme.of(context);
    final variantColor = theme.colorScheme.onSurfaceVariant;
    final style        = theme.textTheme.labelSmall?.copyWith(color: variantColor);

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (owner != null || creation != null)
            Row(children: [
              if (owner != null) ...[
                Icon(Icons.person_outline, size: 14, color: variantColor),
                const SizedBox(width: 4),
                Text(owner!, style: style?.copyWith(fontWeight: FontWeight.w600)),
              ],
              if (owner != null && creation != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: Text('•', style: style),
                ),
              if (creation != null)
                Text(
                  'Created ${FormattingHelper.getRelativeTime(creation)}',
                  style: style,
                ),
            ]),
          if ((modified != null || modifiedBy != null) &&
              (modified != creation || modifiedBy != owner)) ...[
            const SizedBox(height: 4),
            Row(children: [
              if (modifiedBy != null) ...[
                Icon(Icons.edit_outlined, size: 14, color: variantColor),
                const SizedBox(width: 4),
                Text(modifiedBy!,
                    style: style?.copyWith(fontWeight: FontWeight.w600)),
              ],
              if (modifiedBy != null && modified != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0),
                  child: Text('•', style: style),
                ),
              if (modified != null)
                Text(
                  'Modified ${FormattingHelper.getRelativeTime(modified)}',
                  style: style,
                ),
            ]),
          ],
        ],
      ),
    );
  }

  List<Widget> _formChildren(BuildContext context) {
    final theme            = Theme.of(context);
    final colorScheme      = theme.colorScheme;
    final mediaQuery       = MediaQuery.of(context);
    final bottomPadding    = mediaQuery.viewPadding.bottom;
    final viewInsetsBottom = mediaQuery.viewInsets.bottom;

    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$itemCode'
                    '${itemSubtext != null && itemSubtext!.isNotEmpty ? ' • $itemSubtext' : ''}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'ShureTechMono',
                      fontSize: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  itemName,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: colorScheme.onSurface),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                _buildMetadataHeader(context),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _popSheet(context),
            icon: const Icon(Icons.close),
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.surfaceContainerHigh,
              foregroundColor: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),

      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Divider(height: 1),
      ),

      ...customFields.map(
        (w) => Padding(
          padding: const EdgeInsets.only(bottom: 20.0),
          child: w,
        ),
      ),

      // ── Quantity input ─────────────────────────────────────────────────────
      QuantityInputWidget(
        controller: qtyController,
        onIncrement: onIncrement,
        onDecrement: onDecrement,
        isReadOnly: isQtyReadOnly,
        label: 'Quantity',
        widgetTag: itemCode,
        infoText: qtyInfoText,
        onInfoTap: qtyInfoTooltip != null
            ? () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Stock Breakdown'),
                    content: Text(
                      qtyInfoTooltip!,
                      style: const TextStyle(
                          fontFamily: 'ShureTechMono', fontSize: 14),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                )
            : null,
      ),

      const SizedBox(height: 32),

      _AnimatedSaveButton(
        saveButtonState: saveButtonState,
        isSaveEnabled:   isSaveEnabled,
        isSaveEnabledRx: isSaveEnabledRx,
        isLoading:       isLoading,
        title:           title,
        onSubmit: () async {
          final result = onSubmit();
          if (result is Future) await result;
        },
        formKey:  formKey,
        sheetTag: _sheetTag,
      ),

      if (onDelete != null) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () {
              _popSheet(context);
              onDelete!();
            },
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.error,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove Item'),
          ),
        ),
      ],

      SizedBox(height: math.max(viewInsetsBottom, bottomPadding) + 20),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _sheetCtrl;

    final theme       = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery  = MediaQuery.of(context);
    final topPadding  = mediaQuery.viewPadding.top;
    final bottomPadding = mediaQuery.viewPadding.bottom;

    // Drag handle — sits on the same surface as the sheet body.
    final dragHandle = Container(
      color: colorScheme.surface,
      width: double.infinity,
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      alignment: Alignment.center,
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    final scanBar = onScan != null
        ? Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
            child: BarcodeInputWidget(
              onScan: onScan!,
              controller: scanController,
              isLoading: isScanning,
              hintText: 'Scan Rack / Batch / Item',
              isEmbedded: true,
            ),
          )
        : null;

    // Shared decoration — both branches use identical appearance.
    final sheetDecoration = BoxDecoration(
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
    );
    final sheetMargin = EdgeInsets.only(top: topPadding + 12);

    if (scrollController != null) {
      // fix(global-item-sheet): use Flexible(fit: FlexFit.loose) instead of
      // Expanded so the sheet content-hugs when the ListView is shorter than
      // the available space, while still allowing full expansion + scrolling
      // when content overflows (keyboard open, many fields).
      //
      // Expanded forces the ListView to fill ALL remaining space in the Column
      // regardless of mainAxisSize: min — this caused the DN item form sheet
      // to always expand to full-screen height and leave dead whitespace below
      // the Remove Item button.
      //
      // Removing the flex wrapper entirely is not viable — it would give the
      // ListView an unbounded height constraint, causing a Flutter layout
      // error: "Vertical viewport was given unbounded height".
      return Container(
        margin: sheetMargin,
        decoration: sheetDecoration,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            dragHandle,
            Flexible(
              fit: FlexFit.loose,
              child: Form(
                key: formKey,
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  shrinkWrap: true,
                  children: _formChildren(context),
                ),
              ),
            ),
            // if (scanBar != null) scanBar,
          ],
        ),
      );
    } else {
      // Non-scrollable branch: wrap in the same Container so the sheet always
      // owns its opaque background regardless of the call-site backgroundColor.
      return Container(
        margin: sheetMargin,
        decoration: sheetDecoration,
        clipBehavior: Clip.antiAlias,
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dragHandle,
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _formChildren(context),
                ),
              ),
              // if (scanBar != null) scanBar,
            ],
          ),
        ),
      );
    }
  }
}
