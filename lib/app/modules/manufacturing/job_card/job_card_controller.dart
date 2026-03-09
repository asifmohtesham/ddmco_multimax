import 'package:get/get.dart';
import 'package:multimax/app/data/providers/erpnext_provider.dart';
import 'package:multimax/app/modules/manufacturing/models/job_card_model.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';
import 'dart:async';

class JobCardController extends GetxController {
  final ErpnextProvider _provider = Get.find<ErpnextProvider>();

  final RxList<JobCardModel> jobCards = <JobCardModel>[].obs;
  final RxBool isLoading = false.obs;
  final RxString? filterWorkOrder = RxString('');
  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    fetchJobCards();
    _startAutoRefresh();
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }

  void _startAutoRefresh() {
    // Auto-refresh every 30 seconds for active job cards
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (jobCards.any((jc) => jc.isInProgress)) {
        fetchJobCards(silent: true);
      }
    });
  }

  Future<void> fetchJobCards({bool silent = false}) async {
    try {
      if (!silent) isLoading.value = true;

      final filters = <String, dynamic>{};
      if (filterWorkOrder?.value.isNotEmpty ?? false) {
        filters['work_order'] = filterWorkOrder!.value;
      }

      final response = await _provider.get ListWithFilters(
        doctype: 'Job Card',
        fields: [
          'name', 'work_order', 'operation', 'workstation',
          'employee', 'employee_name', 'for_quantity', 'total_completed_qty',
          'process_loss_qty', 'status', 'expected_start_date', 'expected_end_date',
          'actual_start_date', 'actual_end_date', 'total_time_in_mins', 'modified'
        ],
        filters: filters,
        orderBy: 'modified desc',
        limit: 50,
      );

      if (response != null && response['data'] != null) {
        final List<dynamic> data = response['data'];
        
        // Fetch full details for each job card (for time logs and items)
        final List<JobCardModel> fullJobCards = [];
        for (var jcData in data) {
          final fullJc = await _fetchFullJobCard(jcData['name']);
          if (fullJc != null) {
            fullJobCards.add(fullJc);
          }
        }
        
        jobCards.value = fullJobCards;
      }
    } catch (e) {
      if (!silent) {
        GlobalSnackbar.error(message: 'Failed to load job cards: $e');
      }
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  Future<JobCardModel?> _fetchFullJobCard(String name) async {
    try {
      final response = await _provider.getDoc(
        doctype: 'Job Card',
        name: name,
      );

      if (response != null && response['data'] != null) {
        return JobCardModel.fromJson(response['data']);
      }
    } catch (e) {
      // Silent failure for individual job cards
    }
    return null;
  }

  Future<void> startJobCard(String name) async {
    try {
      isLoading.value = true;

      // Create time log entry
      final response = await _provider.runDocMethod(
        doctype: 'Job Card',
        name: name,
        method: 'start_timer',
      );

      if (response != null) {
        GlobalSnackbar.success(message: 'Job card started');
        await fetchJobCards();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to start job card: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> pauseJobCard(String name) async {
    try {
      isLoading.value = true;

      final response = await _provider.runDocMethod(
        doctype: 'Job Card',
        name: name,
        method: 'stop_timer',
      );

      if (response != null) {
        GlobalSnackbar.success(message: 'Job card paused');
        await fetchJobCards();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to pause job card: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> updateCompletedQty(String name, double qty) async {
    try {
      isLoading.value = true;

      // Find current job card
      final jobCard = jobCards.firstWhereOrNull((jc) => jc.name == name);
      if (jobCard == null) return;

      // Update the document
      await _provider.updateDoc(
        doctype: 'Job Card',
        name: name,
        data: {
          'total_completed_qty': (jobCard.totalCompletedQty + qty),
        },
      );

      GlobalSnackbar.success(message: 'Quantity updated: +${qty.toInt()}');
      await fetchJobCards();
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to update quantity: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> completeJobCard(String name) async {
    try {
      isLoading.value = true;

      // Stop timer if running
      final jobCard = jobCards.firstWhereOrNull((jc) => jc.name == name);
      if (jobCard?.hasActiveTimeLog ?? false) {
        await _provider.runDocMethod(
          doctype: 'Job Card',
          name: name,
          method: 'stop_timer',
        );
      }

      // Complete the job card
      await _provider.runDocMethod(
        doctype: 'Job Card',
        name: name,
        method: 'submit',
      );

      GlobalSnackbar.success(message: 'Job card completed');
      await fetchJobCards();
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to complete job card: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void filterByWorkOrder(String? workOrder) {
    filterWorkOrder?.value = workOrder ?? '';
    fetchJobCards();
  }
}