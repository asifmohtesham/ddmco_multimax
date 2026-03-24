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
//
// Private widget that owns the three-state animated save button:
//   idle    — FilledButton with save icon; tappable.
//   loading — orange; spinner; not tappable.
//   success — green; check_circle; not tappable (sheet closing in 700 ms).
//   error   — red; error_outline; not tappable (resets to idle after 1.5 s).
//
// All colour and icon transitions use AnimatedContainer + AnimatedSwitcher
// so there is no explicit AnimationController needed.
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
      final state        = saveButtonState.value;
      final rxEnabled    = isSaveEnabledRx?.value ?? true;
      final canTap       = isSaveEnabled &&
                           rxEnabled &&
                           !isLoading &&
                           state == SaveButtonState.idle;

      // ── Colour per state ─────────────────────────────────────────────────────
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

      // ── Icon / content per state ───────────────────────────────────────────
      final Widget child;
      switch (state) {
        case SaveButtonState.loading:
          child = const SizedBox(
            key: ValueKey('loading'),
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.5,
            ),
          );
        case SaveButtonState.success:
          child = const Icon(
            key: ValueKey('success'),
            Icons.check_circle_outline,
            color: Colors.white,
            size: 24,
          );
        case SaveButtonState.error:
          child = const Icon(
            key: ValueKey('error'),
            Icons.error_outline,
            color: Colors.white,
            size: 24,
          );
        case SaveButtonState.idle:
          child = Row(
            key: const ValueKey('idle'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.save_outlined,
                color: canTap ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: canTap ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant,
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
  final bool isQtyReadOnly;

  final Function onSubmit;
  final VoidCallback? onDelete;

  // State driven by parent DocType controller
  final bool isSaveEnabled;
  final RxBool? isSaveEnabledRx;
  final bool isLoading;

  // Option-3: animated save button state.
  // Defaults to idle so callers not yet wired still compile.
  final Rx<SaveButtonState> saveButtonState;

  // Metadata
  final String? owner;
  final String? creation;
  final String? modified;
  final String? modifiedBy;

  // Scan integration
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
  })  : saveButtonState = saveButtonState ?? SaveButtonState.idle.obs {
    _sheetTag = key != null
        ? key.toString()
        : 'sheet_\${DateTime.now().microsecondsSinceEpoch}';
  }

  // ---------------------------------------------------------------------------
  // Static helper — accessible from DocType-specific customFields builders.
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  ItemFormSheetController get _sheetCtrl =>
      Get.put(ItemFormSheetController(), tag: _sheetTag, permanent: false);

  static void _popSheet(BuildContext context) =>
      Navigator.of(context).pop();

  Widget _buildMetadataHeader(BuildContext context) {
    if (owner == null &&
        creation == null &&
        modified == null &&
        modifiedBy == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final variantColor = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelSmall?.copyWith(color: variantColor);

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (owner != null || creation != null)
            Row(
              children: [
                if (owner != null) ...[
                  Icon(Icons.person_outline, size: 14, color: variantColor),
                  const SizedBox(width: 4),
                  Text(owner!,
                      style:
                          style?.copyWith(fontWeight: FontWeight.w600)),
                ],
                if (owner != null && creation != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Text('•', style: style),
                  ),
                if (creation != null)
                  Text(
                    'Created \${FormattingHelper.getRelativeTime(creation)}',
                    style: style,
                  ),
              ],
            ),
          if ((modified != null || modifiedBy != null) &&
              (modified != creation || modifiedBy != owner)) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                if (modifiedBy != null) ...[
                  Icon(Icons.edit_outlined, size: 14, color: variantColor),
                  const SizedBox(width: 4),
                  Text(modifiedBy!,
                      style:
                          style?.copyWith(fontWeight: FontWeight.w600)),
                ],
                if (modifiedBy != null && modified != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Text('•', style: style),
                  ),
                if (modified != null)
                  Text(
                    'Modified \${FormattingHelper.getRelativeTime(modified)}',
                    style: style,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Form content — shared between both layout modes.
  // ---------------------------------------------------------------------------
  List<Widget> _formChildren(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.viewPadding.bottom;
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
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
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                  ),
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

      QuantityInputWidget(
        controller: qtyController,
        onIncrement: onIncrement,
        onDecrement: onDecrement,
        isReadOnly: isQtyReadOnly,
        label: 'Quantity',
        infoText: qtyInfoText,
      ),

      const SizedBox(height: 32),

      // Option-3: animated save button.
      _AnimatedSaveButton(
        saveButtonState:  saveButtonState,
        isSaveEnabled:    isSaveEnabled,
        isSaveEnabledRx:  isSaveEnabledRx,
        isLoading:        isLoading,
        title:            title,
        onSubmit:         () async {
          final result = onSubmit();
          if (result is Future) await result;
        },
        formKey:          formKey,
        sheetTag:         _sheetTag,
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

      SizedBox(
        height: math.max(viewInsetsBottom, bottomPadding) + 20,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    _sheetCtrl; // register on first build

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.viewPadding.top;
    final bottomPadding = mediaQuery.viewPadding.bottom;

    // ── Drag handle ────────────────────────────────────────────────────────
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

    // ── Scan bar (optional, always below form) ──────────────────────────
    final scanBar = onScan != null
        ? Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, bottomPadding + 12),
            child: BarcodeInputWidget(
              onScan: onScan!,
              controller: scanController,
              isLoading: isScanning,
              hintText: 'Scan Rack / Batch / Item',
              isEmbedded: true,
            ),
          )
        : null;

    // ─────────────────────────────────────────────────────────────────────
    // LAYOUT SWITCH
    //
    // scrollController != null → DraggableScrollableSheet path
    //   The parent provides a finite height (e.g. Stock Entry, Delivery Note).
    //   Use Expanded + ListView so the form fills and scrolls within that
    //   bounded space.
    //
    // scrollController == null → content-hugging SingleChildScrollView path
    //   The parent (ConstrainedBox + SingleChildScrollView) provides unbounded
    //   height to this widget so it can size itself to its content. Using
    //   Expanded here would crash with "RenderFlex children have non-zero flex
    //   but incoming height constraints are unbounded".
    //   Use Column(mainAxisSize: min) + direct children instead.
    // ─────────────────────────────────────────────────────────────────────

    if (scrollController != null) {
      // ── Bounded-height path (Stock Entry, Delivery Note) ──────────────────
      return Container(
        margin: EdgeInsets.only(top: topPadding + 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28.0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            dragHandle,
            Expanded(
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
      // ── Unbounded / content-hugging path (Material Request) ───────────────
      // No top margin or outer radius here — the parent Material widget in
      // openItemSheet() already provides the surface colour and border radius.
      return Form(
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
      );
    }
  }
}
