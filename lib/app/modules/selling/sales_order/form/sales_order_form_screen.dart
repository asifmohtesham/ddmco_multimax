import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/data/utils/formatting_helper.dart';
import 'package:multimax/app/modules/global_widgets/async_action_buttons.dart';
import 'package:multimax/app/modules/global_widgets/barcode_input_widget.dart';
import 'package:multimax/app/modules/global_widgets/doc_detail_row.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/doctype_form_header.dart';
import 'package:multimax/app/modules/global_widgets/form_empty_state.dart';
import 'package:multimax/app/modules/global_widgets/inline_banner.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/global_widgets/realtime_sync_status_icon.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';
import 'package:multimax/app/modules/selling/sales_order/form/sales_order_form_controller.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';
import 'package:multimax/app/modules/selling/sales_order/widgets/so_progress_row.dart';
import 'package:multimax/app/shared/item_card/doc_item_card.dart';
import 'package:multimax/app/shared/item_card/item_card_data.dart';

/// Sales Order form. Mirrors the Purchase Order form's tab/header structure
/// (Task 4 brief), with the NestedScrollView overlap-absorber fix from
/// gotcha-nestedscrollview-form-header.md: without it, a short tab renders
/// blank once the header has collapsed from scrolling a longer tab.
class SalesOrderFormScreen extends GetView<SalesOrderFormController> {
  const SalesOrderFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Every Rx read that feeds the pinned header (or is needed by widgets
    // built inside headerSliverBuilder) is hoisted here: NestedScrollView
    // calls headerSliverBuilder after this builder returns, so an Obx read
    // placed inside it is never tracked (gotcha-nestedscrollview-form-header).
    return Obx(() {
      final s = controller.so.value;
      final isDirty = controller.isDirty.value;
      final isSaving = controller.isSaving.value;
      final saveResult = controller.saveResult.value;
      final isLoading = controller.isLoading.value;
      final bannerText = controller.banner.value;
      final isEditable = controller.isEditable;
      // canSubmit / canSaveNow read so.value + the permission RxMap/RxnBools
      // behind `actions` — hoisting them here (not inside headerSliverBuilder
      // or the Details tab's own Obx) is what makes the Submit button and
      // the header Save icon repaint when a permission probe resolves.
      final canSubmit = controller.canSubmit;
      final canSaveNow = controller.canSaveNow;
      // actions reads so.value + the permission RxMap/RxnBools; hoisted here
      // (not inside the Details tab's own Obx) for the same reason canSubmit
      // is — see the class doc comment.
      final canMakeDn = controller.actions.contains(SoAction.makeDn);

      return PopScope(
        canPop: !isDirty,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await controller.confirmDiscard();
        },
        child: DefaultTabController(
          length: 2,
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                SliverOverlapAbsorber(
                  handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
                  sliver: DocTypeFormHeader(
                    title: s?.name ?? 'Loading...',
                    docType: 'Sales Order',
                    statusLabel: s?.status,
                    canSave: isDirty && isEditable && canSaveNow,
                    docStatus: s?.docstatus ?? 0,
                    isSaving: isSaving,
                    saveResult: saveResult,
                    onSave: (isDirty && isEditable && canSaveNow)
                        ? controller.saveDocument
                        : null,
                    onReload: (controller.mode != 'new' && !isDirty)
                        ? controller.reloadDocument
                        : null,
                    extraActions: [
                      // Carries its own Obx — repaints independently of this
                      // delegate's shouldRebuild (which keys on action count).
                      // Always present (renders SizedBox.shrink() when empty)
                      // so that count stays stable and shouldRebuild doesn't
                      // mis-fire as actions come and go.
                      const _SoActionsMenu(),
                      RealtimeSyncStatusIcon(
                        isConnected: controller.isRealtimeConnected,
                        isSyncing: controller.isRemoteSyncing,
                      ),
                    ],
                    bottom: const TabBar(
                      tabs: [Tab(text: 'Details'), Tab(text: 'Items')],
                    ),
                  ),
                ),
              ],
              body: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : s == null
                      ? const Center(child: Text('Not found'))
                      : TabBarView(
                          children: [
                            _detailsTab(
                                s, isEditable, canSubmit, canMakeDn, bannerText),
                            _itemsTab(s, isEditable, bannerText),
                          ],
                        ),
            ),
          ),
        ),
      );
    });
  }

  // ── Details tab ──────────────────────────────────────────────────────────

  Widget _detailsTab(
    SalesOrder s,
    bool isEditable,
    bool canSubmit,
    bool canMakeDn,
    String? bannerText,
  ) {
    return Builder(builder: (context) {
      return CustomScrollView(
        key: const PageStorageKey('so_details_tab'),
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          _bannerSliver(bannerText),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 24 + MediaQuery.of(context).padding.bottom),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    StatusPill(status: s.status),
                  ],
                ),
                if (s.docstatus == 1) ...[
                  const SizedBox(height: 10),
                  SoProgressRow(
                      perDelivered: s.perDelivered, perBilled: s.perBilled),
                ],
                const SizedBox(height: 16),

                DocPickerField(
                  label: 'Customer',
                  icon: Icons.person_outline,
                  value: s.customerName.isNotEmpty
                      ? s.customerName
                      : s.customer,
                  onTap: isEditable
                      ? () => showLinkSearchSheet(
                          doctype: 'Customer',
                          title: 'Select Customer',
                          onSelected: controller.setCustomer)
                      : null,
                ),
                const SizedBox(height: 12),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: DocPickerField(
                        label: 'Transaction Date',
                        icon: Icons.event_outlined,
                        value: s.transactionDate,
                        trailingIcon: Icons.edit_calendar_outlined,
                        onTap: isEditable
                            ? () => _pickDate(
                                context,
                                initial: s.transactionDate,
                                onPicked: (d) =>
                                    controller.setHeader(transactionDate: d))
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DocPickerField(
                        label: 'Delivery Date',
                        icon: Icons.local_shipping_outlined,
                        value: s.deliveryDate,
                        placeholder: 'Not set',
                        trailingIcon: Icons.edit_calendar_outlined,
                        onTap: isEditable
                            ? () => _pickDate(
                                context,
                                initial: s.deliveryDate ?? s.transactionDate,
                                firstDate: s.transactionDate,
                                onPicked: (d) =>
                                    controller.setHeader(deliveryDate: d))
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                DocPickerField(
                  label: 'Order Type',
                  icon: Icons.sell_outlined,
                  value: s.orderType,
                  onTap: isEditable
                      ? () => showOptionPickerSheet(
                            context,
                            title: 'Order Type',
                            options: const ['Sales', 'Shopping Cart'],
                            selected: s.orderType,
                            onSelected: (v) =>
                                controller.setHeader(orderType: v),
                          )
                      : null,
                ),
                const SizedBox(height: 12),

                DocPickerField(
                  label: 'Price List',
                  icon: Icons.sell_outlined,
                  value: s.sellingPriceList,
                  placeholder: 'Select',
                  onTap: isEditable
                      ? () => showLinkSearchSheet(
                          doctype: 'Price List',
                          title: 'Select Price List',
                          filters: const {'selling': 1, 'enabled': 1},
                          onSelected: controller.setPriceList)
                      : null,
                ),
                const Divider(height: 20),

                DocPickerField(
                  label: 'Set Warehouse',
                  icon: Icons.warehouse_outlined,
                  value: s.setWarehouse,
                  placeholder: 'Not set',
                  onTap: isEditable
                      ? () => showLinkSearchSheet(
                          doctype: 'Warehouse',
                          title: 'Select Warehouse',
                          onSelected: (v) =>
                              controller.setHeader(setWarehouse: v))
                      : null,
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: controller.poNoController,
                  enabled: isEditable,
                  decoration: const InputDecoration(
                    labelText: "Customer's PO No",
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                  onChanged: (v) => controller.setHeader(poNo: v),
                ),
                const Divider(height: 28),

                DocDetailRow(
                    label: 'Total Qty', value: _qty(s.totalQty)),
                DocDetailRow(
                    label: 'Taxes',
                    value: _money(s.totalTaxesAndCharges, s.currency)),
                DocDetailRow(
                    label: 'Grand Total',
                    value: _money(s.grandTotal, s.currency)),
                DocDetailRow(
                    label: 'Rounded Total',
                    value: _money(s.roundedTotal, s.currency)),

                if (isEditable && canSubmit) ...[
                  const SizedBox(height: 20),
                  AsyncFilledButton(
                    busy: controller.isSubmitting,
                    onPressed: controller.submitDocument,
                    icon: const Icon(Icons.check_circle_outline),
                    label: 'Submit',
                    loadingLabel: 'Submitting…',
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ],
                if (canMakeDn) ...[
                  const SizedBox(height: 20),
                  AsyncFilledButton(
                    busy: controller.isMakingDn,
                    onPressed: controller.makeDeliveryNote,
                    icon: const Icon(Icons.local_shipping_outlined),
                    label: 'Create Delivery Note',
                    loadingLabel: 'Creating…',
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ],
              ]),
            ),
          ),
        ],
      );
    });
  }

  /// Renders the header/save error banner right after each tab's own
  /// `SliverOverlapInjector`, so it is visible from both Details and Items
  /// (`openItemSheet`'s no-customer guard and `saveDocument`'s validation
  /// errors are both reached from the Items tab). Wrapping the whole
  /// `TabBarView` in a `Column` instead would break the injector's overlap
  /// geometry — see gotcha-nestedscrollview-form-header.md — so this is
  /// duplicated per tab instead. `InlineBanner` itself collapses to zero
  /// height (`SizedBox.shrink`) when `visible` is false, so this is safe to
  /// always include.
  static Widget _bannerSliver(String? bannerText) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      sliver: SliverToBoxAdapter(
        child: InlineBanner(
          visible: bannerText != null,
          message: bannerText ?? '',
          type: BannerType.error,
        ),
      ),
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

  static String _money(double v, String currency) =>
      '${FormattingHelper.getCurrencySymbol(currency)} ${v.toStringAsFixed(2)}';

  Future<void> _pickDate(
    BuildContext context, {
    required String initial,
    String? firstDate,
    required ValueChanged<String> onPicked,
  }) async {
    final parsedInitial = DateTime.tryParse(initial) ?? DateTime.now();
    final parsedFirst =
        firstDate != null ? DateTime.tryParse(firstDate) : null;
    final picked = await showDatePicker(
      context: context,
      initialDate: parsedInitial,
      firstDate: parsedFirst ?? DateTime(parsedInitial.year - 5),
      lastDate: DateTime(parsedInitial.year + 5),
    );
    if (picked != null) {
      onPicked(FormattingHelper.formatDate(picked));
    }
  }

  // ── Items tab ────────────────────────────────────────────────────────────

  Widget _itemsTab(SalesOrder s, bool isEditable, String? bannerText) {
    final items = s.items;
    return Builder(builder: (context) {
      return Column(
        children: [
          Expanded(
            child: CustomScrollView(
              key: const PageStorageKey('so_items_tab'),
              slivers: [
                SliverOverlapInjector(
                  handle:
                      NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                ),
                _bannerSliver(bannerText),
                if (items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: FormEmptyState(
                      icon: Icons.inventory_2_outlined,
                      message: 'No items in this order.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final item = items[index];
                          controller.ensureItemKey(item);
                          final key = controller.itemKeys[item.name];
                          return _itemRow(item, index, key, isEditable);
                        },
                        childCount: items.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isEditable) ...[
            Obx(() => BarcodeInputWidget(
                  onScan: controller.scanBarcode,
                  isLoading: controller.isScanning.value,
                  controller: controller.barcodeController,
                  hintText: 'Scan Item Code',
                  activeRoute: AppRoutes.SALES_ORDER_FORM,
                )),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton.icon(
                  onPressed: () => showLinkSearchSheet(
                    doctype: 'Item',
                    title: 'Select Item',
                    onSelected: (c) => controller.openItemSheet(itemCode: c),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
          ] else
            SizedBox(height: MediaQuery.paddingOf(context).bottom),
        ],
      );
    });
  }

  Widget _itemRow(
    SalesOrderItem item,
    int index,
    GlobalKey? key,
    bool isEditable,
  ) {
    return Obx(() {
      final isHighlighted =
          controller.recentlyAddedItemName.value == item.name;
      final cardData = ItemCardData.fromSalesOrderItem(
        item,
        index: index,
        isEditable: isEditable,
        isHighlighted: isHighlighted,
      );

      return Dismissible(
        key: ValueKey(item.name ?? index),
        direction: isEditable
            ? DismissDirection.endToStart
            : DismissDirection.none,
        confirmDismiss: (_) async {
          controller.deleteItem(item);
          return false; // deleteItem shows its own confirm + mutates state.
        },
        background: Builder(builder: (context) {
          return Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: AppColors.red500,
            child: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.onError, size: 28),
          );
        }),
        child: DocItemCard(
          key: key,
          data: cardData,
          onTap: isEditable ? () => controller.openItemSheet(row: item) : null,
          onDelete: isEditable ? () => controller.deleteItem(item) : null,
        ),
      );
    });
  }
}

// ── Header action menu ──────────────────────────────────────────────────────

/// Lifecycle-action overflow menu for `DocTypeFormHeader.extraActions`.
/// Carries its own `Obx` (per gotcha-nestedscrollview-form-header.md — the
/// header delegate's `shouldRebuild` only keys on `extraActions.length`, not
/// its contents) so Hold/Resume/Close/Re-open/Cancel/Create Delivery Note
/// enable/disable and the spinner swap repaint independently. It is always
/// present in the `extraActions` list — rendering `SizedBox.shrink()` when
/// there is nothing to show — so that length never changes.
class _SoActionsMenu extends GetView<SalesOrderFormController> {
  const _SoActionsMenu();

  static const _labels = {
    SoAction.hold: 'Hold',
    SoAction.resume: 'Resume',
    SoAction.close: 'Close',
    SoAction.reopen: 'Re-open',
    SoAction.cancel: 'Cancel',
    SoAction.makeDn: 'Create Delivery Note',
  };

  static const _destructive = {SoAction.close, SoAction.cancel};

  void _onSelected(SoAction a) {
    switch (a) {
      case SoAction.hold:
        controller.hold();
      case SoAction.resume:
        controller.resume();
      case SoAction.close:
        controller.close();
      case SoAction.reopen:
        controller.reopen();
      case SoAction.cancel:
        controller.cancelDocument();
      case SoAction.makeDn:
        controller.makeDeliveryNote();
      case SoAction.save:
      case SoAction.submit:
        break; // handled by the header's own Save / Details tab's Submit.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final menuActions = controller.actions
          .where((a) => a != SoAction.save && a != SoAction.submit)
          .toList();
      if (controller.isActing.value != null) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      if (menuActions.isEmpty) return const SizedBox.shrink();
      final destructiveColor = Theme.of(context).brightness == Brightness.dark
          ? AppColors.red300
          : AppColors.red700;
      return PopupMenuButton<SoAction>(
        icon: const Icon(Icons.more_vert),
        onSelected: _onSelected,
        itemBuilder: (context) => [
          for (final a in menuActions)
            PopupMenuItem(
              value: a,
              child: Text(
                _labels[a] ?? a.name,
                style: _destructive.contains(a)
                    ? TextStyle(color: destructiveColor)
                    : null,
              ),
            ),
        ],
      );
    });
  }
}
