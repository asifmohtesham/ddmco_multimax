import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:multimax/app/modules/global_widgets/doc_picker_field.dart';
import 'package:multimax/app/modules/global_widgets/global_filter_bottom_sheet.dart';
import 'package:multimax/app/modules/global_widgets/link_search_sheet.dart';
import 'package:multimax/app/modules/global_widgets/option_picker_sheet.dart';
import 'package:multimax/app/modules/global_widgets/user_picker_sheet.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_controller.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';

class SalesOrderFilterBottomSheet extends StatefulWidget {
  const SalesOrderFilterBottomSheet({super.key});

  @override
  State<SalesOrderFilterBottomSheet> createState() =>
      _SalesOrderFilterBottomSheetState();
}

class _SalesOrderFilterBottomSheetState
    extends State<SalesOrderFilterBottomSheet> {
  final SalesOrderController controller = Get.find();

  final customer = RxnString();
  final status = RxnString();
  final from = RxnString();
  final to = RxnString();
  final owner = RxnString();
  final ownerName = RxnString();

  /// The incoming `status` filter when it wasn't a plain String — e.g. the
  /// dashboard's `['in', [...]]`. Kept so Apply can write it back unchanged
  /// when the user doesn't pick a new status from the picker (otherwise it
  /// would silently vanish the moment any other field changes and the user
  /// taps Apply — see F4).
  dynamic _originalNonStringStatus;

  @override
  void initState() {
    super.initState();
    controller.fetchUsers();

    final f = controller.activeFilters;
    final c = f['customer'];
    if (c is String && c.isNotEmpty) customer.value = c;
    final s = f['status'];
    if (s is String && s.isNotEmpty) {
      status.value = s;
    } else if (s != null) {
      _originalNonStringStatus = s;
    }
    // Restores all three shapes the list/dashboard can send: a two-sided
    // ['between', [from, to]], or a one-sided ['>=', d] / ['<=', d] — the
    // one-sided forms used to be dropped entirely (F4).
    final parsed = parseDeliveryDateFilter(f['delivery_date']);
    from.value = parsed.from;
    to.value = parsed.to;
    final o = f['owner'];
    if (o is String && o.isNotEmpty) {
      owner.value = o;
      final match = controller.users.firstWhereOrNull((u) => u.email == o);
      ownerName.value = match?.name ?? o;
    }
  }

  int get _activeCount =>
      [
        customer.value,
        status.value,
        from.value,
        to.value,
        owner.value,
      ].where((v) => v != null && v.isNotEmpty).length +
      (status.value == null && _originalNonStringStatus != null ? 1 : 0);

  Future<void> _pickDate(RxnString target) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      target.value = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  void _applyFilters() {
    final f = <String, dynamic>{};
    if ((customer.value ?? '').isNotEmpty) f['customer'] = customer.value;
    if ((status.value ?? '').isNotEmpty) {
      f['status'] = status.value;
    } else if (_originalNonStringStatus != null) {
      // The user didn't pick a new status via the picker — keep whatever
      // non-String filter (e.g. the dashboard's ['in', [...]]) came in.
      f['status'] = _originalNonStringStatus;
    }
    if ((owner.value ?? '').isNotEmpty) f['owner'] = owner.value;

    final f0 = from.value;
    final t0 = to.value;
    if ((f0 ?? '').isNotEmpty && (t0 ?? '').isNotEmpty) {
      f['delivery_date'] = ['between', [f0, t0]];
    } else if ((f0 ?? '').isNotEmpty) {
      f['delivery_date'] = ['>=', f0];
    } else if ((t0 ?? '').isNotEmpty) {
      f['delivery_date'] = ['<=', t0];
    }

    controller.applyFilters(f);
    Get.back();
  }

  void _clear() {
    customer.value = null;
    status.value = null;
    _originalNonStringStatus = null;
    from.value = null;
    to.value = null;
    owner.value = null;
    ownerName.value = null;
    controller.clearFilters();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => GlobalFilterBottomSheet(
          title: 'Filter Sales Orders',
          activeFilterCount: _activeCount,
          sortOptions: const [],
          currentSortField: '',
          currentSortOrder: 'desc',
          onSortChanged: (_, __) {},
          onApply: _applyFilters,
          onClear: _clear,
          filterWidgets: [
            Obx(() => DocPickerField(
                  label: 'Customer',
                  icon: Icons.person_outline,
                  value: customer.value,
                  onTap: () => showLinkSearchSheet(
                    doctype: 'Customer',
                    title: 'Select Customer',
                    onSelected: (v) => customer.value = v,
                  ),
                )),
            const SizedBox(height: 12),
            Obx(() => DocPickerField(
                  label: 'Status',
                  icon: Icons.flag_outlined,
                  value: status.value ??
                      (_originalNonStringStatus != null
                          ? statusFilterLabel(_originalNonStringStatus)
                          : null),
                  onTap: () => showOptionPickerSheet(
                    context,
                    title: 'Status',
                    options: SalesOrderController.statusChips,
                    selected: status.value ?? '',
                    onSelected: (v) => status.value = v,
                  ),
                )),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Obx(() => DocPickerField(
                        label: 'From',
                        icon: Icons.event_outlined,
                        trailingIcon: Icons.edit_calendar_outlined,
                        value: from.value,
                        onTap: () => _pickDate(from),
                      )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Obx(() => DocPickerField(
                        label: 'To',
                        icon: Icons.event_outlined,
                        trailingIcon: Icons.edit_calendar_outlined,
                        value: to.value,
                        onTap: () => _pickDate(to),
                      )),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Obx(() => DocPickerField(
                  label: 'Owner',
                  icon: Icons.person_search_outlined,
                  value: ownerName.value,
                  onTap: () => Get.bottomSheet(
                    Obx(() => UserPickerSheet(
                          title: 'Select Owner',
                          users: controller.users,
                          isLoading: controller.isFetchingUsers.value,
                          onSelected: (id, display) {
                            owner.value = id;
                            ownerName.value = display;
                            Get.back();
                          },
                        )),
                    isScrollControlled: true,
                  ),
                )),
          ],
        ));
  }
}
