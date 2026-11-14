import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/home/home_controller.dart';

/// A submitted Sales Order that still has something to deliver.
class OpenSalesOrder {
  final String name;
  final String customer;
  final String customerName;
  final DateTime? deliveryDate;
  final double perDelivered;
  final double totalQty;

  const OpenSalesOrder({
    required this.name,
    required this.customer,
    required this.customerName,
    this.deliveryDate,
    required this.perDelivered,
    required this.totalQty,
  });

  factory OpenSalesOrder.fromJson(Map<String, dynamic> j) => OpenSalesOrder(
        name: (j['name'] ?? '').toString(),
        customer: (j['customer'] ?? '').toString(),
        customerName: (j['customer_name'] ?? j['customer'] ?? '').toString(),
        deliveryDate: DateTime.tryParse('${j['delivery_date']}'),
        perDelivered: (j['per_delivered'] as num?)?.toDouble() ?? 0,
        totalQty: (j['total_qty'] as num?)?.toDouble() ?? 0,
      );

  bool matches(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    return name.toLowerCase().contains(s) ||
        customer.toLowerCase().contains(s) ||
        customerName.toLowerCase().contains(s);
  }
}

enum DueState { overdue, today, upcoming, none }

DueState dueStateOf(DateTime? due, DateTime now) {
  if (due == null) return DueState.none;
  final d = DateTime(due.year, due.month, due.day);
  final t = DateTime(now.year, now.month, now.day);
  if (d.isBefore(t)) return DueState.overdue;
  if (d == t) return DueState.today;
  return DueState.upcoming;
}

/// Dashboard → Sales Order: pick an open order to deliver. Most urgent
/// (earliest delivery date) first; tapping one opens its Delivery Note.
class SalesOrderPickSheet extends GetView<HomeController> {
  const SalesOrderPickSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        final scheme = context.scheme;
        return Container(
          decoration: BoxDecoration(
            color: scheme.fg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Deliver a Sales Order',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.text)),
                          const SizedBox(height: 2),
                          Text('Pick an order, then scan its items.',
                              style: TextStyle(
                                  fontSize: 13, color: scheme.textMuted)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Get.back(),
                      icon: Icon(Icons.close, color: scheme.textMuted),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  key: const Key('so_pick_search'),
                  onChanged: controller.filterOpenSalesOrders,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search order or customer',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: scheme.subtle,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: scheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: scheme.border),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              Expanded(
                child: Obx(() {
                  if (controller.isFetchingOpenSalesOrders.value &&
                      controller.openSalesOrders.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final orders = controller.openSalesOrders;
                  if (orders.isEmpty) {
                    return _EmptyState(
                      searching: controller.openSalesOrderQuery.value.isNotEmpty,
                      onRefresh: controller.fetchOpenSalesOrders,
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: controller.fetchOpenSalesOrders,
                    child: Scrollbar(
                      controller: scrollController,
                      child: ListView.builder(
                        controller: scrollController,
                        padding: EdgeInsets.fromLTRB(12, 4, 12, 16 + bottomInset),
                        itemCount: orders.length + 1,
                        itemBuilder: (context, i) {
                          if (i == orders.length) {
                            return _EndMarker(count: orders.length);
                          }
                          final so = orders[i];
                          return Obx(() => _OrderTile(
                                order: so,
                                isOpening:
                                    controller.openingSalesOrder.value == so.name,
                                onTap: () => controller.openSalesOrderDelivery(so),
                              ));
                        },
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OrderTile extends StatelessWidget {
  final OpenSalesOrder order;
  final bool isOpening;
  final VoidCallback onTap;

  const _OrderTile({
    required this.order,
    required this.isOpening,
    required this.onTap,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final due = dueStateOf(order.deliveryDate, DateTime.now());
    final d = order.deliveryDate;
    final dateText = d == null ? 'No date' : '${d.day} ${_months[d.month - 1]}';

    final (Color base, Color ink, String label) = switch (due) {
      DueState.overdue => (AppColors.red500,
          isDark ? AppColors.red300 : AppColors.red700, 'Overdue · $dateText'),
      DueState.today => (AppColors.orange500,
          isDark ? AppColors.orange300 : AppColors.orange700, 'Due today'),
      DueState.upcoming => (AppColors.blue500,
          isDark ? AppColors.blue300 : AppColors.blue700, 'Due $dateText'),
      DueState.none => (AppColors.gray500, scheme.textMuted, dateText),
    };
    final pct = order.perDelivered.clamp(0, 100) / 100;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: scheme.fg,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isOpening ? null : onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        order.name,
                        style: TextStyle(fontSize: 12.5, color: scheme.textMuted),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: base.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: base.withValues(alpha: 0.35)),
                            ),
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: ink)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: pct.toDouble(),
                                minHeight: 5,
                                backgroundColor: scheme.subtle,
                                valueColor:
                                    const AlwaysStoppedAnimation(AppColors.green500),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${order.perDelivered.round()}% sent',
                            style: TextStyle(
                                fontSize: 11.5, color: scheme.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: isOpening
                      ? Padding(
                          padding: const EdgeInsets.all(5),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: scheme.primary),
                        )
                      : Icon(Icons.chevron_right, color: scheme.textSubtle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EndMarker extends StatelessWidget {
  final int count;
  const _EndMarker({required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: scheme.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'End of list · $count open order${count == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: scheme.textMuted),
            ),
          ),
          Expanded(child: Divider(color: scheme.border)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool searching;
  final Future<void> Function() onRefresh;
  const _EmptyState({required this.searching, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 56, color: scheme.textSubtle),
            const SizedBox(height: 12),
            Text(
              searching ? 'No matching orders' : 'No orders waiting for delivery',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: scheme.text),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? 'Try a different order number or customer.'
                  : 'Submitted Sales Orders with items left to deliver show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.textMuted),
            ),
            if (!searching) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
