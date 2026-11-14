import 'package:get/get.dart';
import 'package:multimax/app/data/providers/pricing_rule_provider.dart';
import 'package:multimax/app/modules/pricing/pricing_rule/pricing_rule_controller.dart';

class PricingRuleBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<PricingRuleProvider>()) {
      Get.lazyPut<PricingRuleProvider>(() => PricingRuleProvider(), fenix: true);
    }
    Get.lazyPut<PricingRuleController>(() => PricingRuleController());
  }
}
