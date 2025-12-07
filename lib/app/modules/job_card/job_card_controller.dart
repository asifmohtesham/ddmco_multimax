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
}