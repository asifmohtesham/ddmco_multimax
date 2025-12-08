import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/bom_model.dart';
import 'package:ddmco_multimax/app/data/providers/bom_provider.dart';

class BomController extends GetxController {
  final BomProvider _provider = Get.find<BomProvider>();
  var boms = <BOM>[].obs;
  var isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    fetchBOMs();
  }

  Future<void> fetchBOMs() async {
    isLoading.value = true;
    try {
      final response = await _provider.getBOMs();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        boms.value = data.map((json) => BOM.fromJson(json)).toList();
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch BOMs: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // --- KPI Getters ---

  int get totalBoms => boms.length;

  int get activeBomsCount => boms.where((b) => b.isActive == 1).length;

  double get activeRate => totalBoms > 0 ? activeBomsCount / totalBoms : 0.0;

  double get averageCost {
    if (totalBoms == 0) return 0.0;
    final total = boms.fold(0.0, (sum, b) => sum + b.totalCost);
    return total / totalBoms;
  }

  // Returns top 5 most expensive BOMs
  List<BOM> get topCostBoms {
    final sorted = List<BOM>.from(boms);
    sorted.sort((a, b) => b.totalCost.compareTo(a.totalCost));
    return sorted.take(5).toList();
  }
}