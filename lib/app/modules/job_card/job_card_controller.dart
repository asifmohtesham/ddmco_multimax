import 'package:get/get.dart';
import 'package:ddmco_multimax/app/data/models/job_card_model.dart';
import 'package:ddmco_multimax/app/data/providers/job_card_provider.dart';

class JobCardController extends GetxController {
  final JobCardProvider _provider = Get.find<JobCardProvider>();
  var jobCards = <JobCard>[].obs;
  var isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    fetchJobCards();
  }

  Future<void> fetchJobCards() async {
    isLoading.value = true;
    try {
      final response = await _provider.getJobCards();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        jobCards.value = data.map((json) => JobCard.fromJson(json)).toList();
      }
    } catch (e) {
      Get.snackbar('Error', 'Failed to fetch Job Cards: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // --- KPIs ---

  int get totalCards => jobCards.length;
  int get openCards => jobCards.where((c) => c.status == 'Open' || c.status == 'Work In Progress').length;
  int get completedCards => jobCards.where((c) => c.status == 'Completed').length;

  double get totalPlannedQty => jobCards.fold(0.0, (sum, c) => sum + c.forQuantity);
  double get totalCompletedQty => jobCards.fold(0.0, (sum, c) => sum + c.totalCompletedQty);

  // Group by Operation for Insights
  Map<String, int> get operationBreakdown {
    final Map<String, int> stats = {};
    for (var card in jobCards) {
      stats[card.operation] = (stats[card.operation] ?? 0) + 1;
    }
    return stats;
  }
}