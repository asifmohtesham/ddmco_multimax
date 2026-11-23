import 'dart:async';

import 'package:get/get.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

class SuppliersByItemController extends GetxController {
  SuppliersByItemController({
    required ApiProvider api,
    SuppliersByItemFilters initialFilters = const SuppliersByItemFilters(),
  }) : _api = api,
       filters = initialFilters.obs;

  final ApiProvider _api;
  final Rx<SuppliersByItemFilters> filters;
  final activeFilters = <String, String>{}.obs;
  final nodes = <SuppliersByItemNode>[].obs;
  final isLoading = false.obs;
  final error = RxnString();

  @override
  void onInit() {
    super.onInit();
    unawaited(run());
  }

  Future<void> run({SuppliersByItemFilters? filters}) async {
    if (isClosed || isLoading.value) return;

    isLoading.value = true;
    try {
      final selected = filters ?? this.filters.value;
      this.filters.value = selected;
      activeFilters.assignAll(
        selected.toJson().map((key, value) {
          return MapEntry(key, switch (value) {
            [final String code] => code,
            List<String> codes => '${codes.length} selected',
            _ => value.toString(),
          });
        }),
      );
      error.value = null;
      nodes.clear();
      if (selected.hasInvalidDateRange) {
        error.value = SuppliersByItemReportException.invalidDateRange;
        return;
      }

      final result = await _api.runSuppliersByItem(selected);
      if (!isClosed) nodes.assignAll(result);
    } on SuppliersByItemReportException catch (e) {
      if (!isClosed) error.value = e.message;
    } catch (_) {
      if (!isClosed) error.value = 'Could not load Suppliers by Item.';
    } finally {
      if (!isClosed) isLoading.value = false;
    }
  }
}
