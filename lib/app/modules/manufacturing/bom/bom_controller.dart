import 'package:get/get.dart';
import 'package:multimax/app/data/models/manufacturing/bom_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class BomController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Observables
  final RxBool isLoading = false.obs;
  final RxBool isLoadingDetail = false.obs;
  final RxList<BomModel> bomList = <BomModel>[].obs;
  final Rx<BomModel?> selectedBom = Rx<BomModel?>(null);
  final RxString searchQuery = ''.obs;
  final RxString filterStatus = 'All'.obs; // All, Active, Inactive

  @override
  void onInit() {
    super.onInit();
    fetchBomList();
  }

  /// Fetch BOM list with filters
  Future<void> fetchBomList() async {
    try {
      isLoading.value = true;
      
      final filters = <String, dynamic>{
        'docstatus': 1, // Submitted only
      };

      if (filterStatus.value == 'Active') {
        filters['is_active'] = 1;
      } else if (filterStatus.value == 'Inactive') {
        filters['is_active'] = 0;
      }

      if (searchQuery.value.isNotEmpty) {
        // Search by item code or name
      }

      final response = await _apiProvider.get(
        '/api/resource/BOM',
        queryParameters: {
          'fields': '[
            "name", "item", "item_name", "description", "quantity", "uom", 
            "is_active", "is_default", "total_cost", "with_operations", 
            "image", "modified", "creation"
          ]',
          'filters': filters,
          'limit_page_length': 100,
        },
      );

      if (response.statusCode == 200) {
        final data = response.body['data'] as List;
        bomList.value = data.map((json) => BomModel.fromJson(json)).toList();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load BOM list: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// Fetch BOM detail
  Future<void> fetchBomDetail(String bomName) async {
    try {
      isLoadingDetail.value = true;

      final response = await _apiProvider.get('/api/resource/BOM/$bomName');

      if (response.statusCode == 200) {
        selectedBom.value = BomModel.fromJson(response.body['data']);
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load BOM details: $e');
    } finally {
      isLoadingDetail.value = false;
    }
  }

  /// Set filter status
  void setFilterStatus(String status) {
    filterStatus.value = status;
    fetchBomList();
  }

  /// Search BOM
  void searchBom(String query) {
    searchQuery.value = query;
    fetchBomList();
  }

  /// Navigate to BOM detail
  void goToBomDetail(String bomName) {
    Get.toNamed('/manufacturing/bom/$bomName');
  }
}
