import 'package:get/get.dart';
import 'package:multimax/app/data/providers/erpnext_provider.dart';
import 'package:multimax/app/modules/manufacturing/models/bom_model.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class BomController extends GetxController {
  final ErpnextProvider _provider = Get.find<ErpnextProvider>();

  final RxList<BomModel> boms = <BomModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxString searchQuery = ''.obs;

  @override
  void onInit() {
    super.onInit();
    fetchBoms();
  }

  Future<void> fetchBoms({bool silent = false}) async {
    try {
      if (!silent) isLoading.value = true;

      final filters = <String, dynamic>{
        'is_active': 1,
      };

      if (searchQuery.value.isNotEmpty) {
        filters['item'] = ['like', '%${searchQuery.value}%'];
      }

      final response = await _provider.getListWithFilters(
        doctype: 'BOM',
        fields: [
          'name', 'item', 'item_name', 'quantity', 'uom',
          'is_active', 'is_default', 'company', 'total_cost',
          'operating_cost', 'raw_material_cost', 'description', 'modified'
        ],
        filters: filters,
        orderBy: 'modified desc',
        limit: 50,
      );

      if (response != null && response['data'] != null) {
        final List<dynamic> data = response['data'];
        
        // Fetch full BOM details including items and operations
        final List<BomModel> fullBoms = [];
        for (var bomData in data) {
          final fullBom = await _fetchFullBom(bomData['name']);
          if (fullBom != null) {
            fullBoms.add(fullBom);
          }
        }
        
        boms.value = fullBoms;
      }
    } catch (e) {
      if (!silent) {
        GlobalSnackbar.error(message: 'Failed to load BOMs: $e');
      }
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  Future<BomModel?> _fetchFullBom(String name) async {
    try {
      final response = await _provider.getDoc(
        doctype: 'BOM',
        name: name,
      );

      if (response != null && response['data'] != null) {
        return BomModel.fromJson(response['data']);
      }
    } catch (e) {
      // Silent failure for individual BOMs
    }
    return null;
  }

  void searchBoms(String query) {
    searchQuery.value = query;
    fetchBoms();
  }
}