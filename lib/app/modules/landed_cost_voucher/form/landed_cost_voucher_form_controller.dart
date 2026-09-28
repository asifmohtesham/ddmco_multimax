import 'package:get/get.dart';
import 'package:multimax/app/data/models/landed_cost_voucher_model.dart';
import 'package:multimax/app/data/providers/landed_cost_voucher_provider.dart';
import 'package:multimax/app/core/utils/app_notification.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// Loads one Landed Cost Voucher for display. The app does not create or
/// edit vouchers — that happens in ERPNext Desk — so there is no save path.
class LandedCostVoucherFormController extends GetxController {
  final LandedCostVoucherProvider _provider =
      Get.find<LandedCostVoucherProvider>();

  final String name = Get.arguments?['name'] ?? '';

  var isLoading = true.obs;

  var voucher = Rx<LandedCostVoucher?>(null);
  var docMeta = <String, dynamic>{}.obs;
  var isMetaLoaded = false.obs;

  @override
  void onInit() {
    super.onInit();
    _fetchMeta();
    fetchDocument();
  }

  Future<void> _fetchMeta() async {
    try {
      final res = await Get.find<ApiProvider>().getDocTypeMeta('Landed Cost Voucher');
      if (res.statusCode == 200 && res.data['docs'] != null && res.data['docs'].isNotEmpty) {
        docMeta.value = res.data['docs'][0];
        isMetaLoaded.value = true;
      }
    } catch (e) {
      // Labels fall back to their defaults when meta cannot be loaded.
    }
  }

  Future<void> fetchDocument() async {
    isLoading.value = true;
    try {
      final response = await _provider.getLandedCostVoucher(name);
      if (response.statusCode == 200 && response.data['data'] != null) {
        voucher.value = LandedCostVoucher.fromJson(response.data['data']);
      } else {
        AppNotification.error('Failed to load document');
      }
    } catch (e) {
      AppNotification.error('Error loading document: $e');
    } finally {
      isLoading.value = false;
    }
  }
}
