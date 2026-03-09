import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/manufacturing/job_card_model.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

class JobCardController extends GetxController {
  final ApiProvider _apiProvider = Get.find<ApiProvider>();

  // Observables
  final RxBool isLoading = false.obs;
  final RxBool isLoadingDetail = false.obs;
  final RxBool isProcessing = false.obs;
  final RxList<JobCardModel> jobCardList = <JobCardModel>[].obs;
  final RxList<JobCardModel> activeJobCards = <JobCardModel>[].obs;
  final Rx<JobCardModel?> selectedJobCard = Rx<JobCardModel?>(null);
  final RxString searchQuery = ''.obs;
  final RxString filterStatus = 'All'.obs; // All, Open, Work in Progress, Completed, On Hold

  // Time tracking
  final Rx<DateTime?> currentStartTime = Rx<DateTime?>(null);
  Timer? _refreshTimer;
  Timer? _timeTrackingTimer;
  final RxString elapsedTime = '00:00:00'.obs;

  // Input controllers
  final TextEditingController completedQtyController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    fetchJobCardList();
    _startAutoRefresh();
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    _timeTrackingTimer?.cancel();
    completedQtyController.dispose();
    remarksController.dispose();
    super.onClose();
  }

  /// Auto-refresh every 30 seconds for active job cards
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (filterStatus.value == 'Work in Progress' || filterStatus.value == 'Open') {
        fetchJobCardList(silent: true);
        fetchActiveJobCards(silent: true);
      }
    });
  }

  /// Start time tracking timer
  void _startTimeTracking() {
    _timeTrackingTimer?.cancel();
    _timeTrackingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (currentStartTime.value != null) {
        final duration = DateTime.now().difference(currentStartTime.value!);
        elapsedTime.value = _formatDuration(duration);
      }
    });
  }

  /// Format duration to HH:MM:SS
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  /// Fetch Job Card list
  Future<void> fetchJobCardList({bool silent = false}) async {
    try {
      if (!silent) isLoading.value = true;

      final filters = <String, dynamic>{
        'docstatus': ['<', 2], // Draft and Submitted
      };

      if (filterStatus.value != 'All') {
        filters['status'] = filterStatus.value;
      }

      final response = await _apiProvider.get(
        '/api/resource/Job Card',
        queryParameters: {
          'fields': '[
            "name", "work_order", "operation", "workstation", "status",
            "production_item", "item_name", "for_quantity", "total_completed_qty",
            "total_time_in_mins", "expected_time_in_mins", "sequence_id",
            "posting_date", "modified", "creation"
          ]',
          'filters': filters,
          'order_by': 'sequence_id asc, creation desc',
          'limit_page_length': 100,
        },
      );

      if (response.statusCode == 200) {
        final data = response.body['data'] as List;
        jobCardList.value = data.map((json) => JobCardModel.fromJson(json)).toList();
      }
    } catch (e) {
      if (!silent) {
        GlobalSnackbar.error(message: 'Failed to load Job Cards: $e');
      }
    } finally {
      if (!silent) isLoading.value = false;
    }
  }

  /// Fetch active Job Cards (Work in Progress)
  Future<void> fetchActiveJobCards({bool silent = false}) async {
    try {
      final response = await _apiProvider.get(
        '/api/resource/Job Card',
        queryParameters: {
          'fields': '[
            "name", "work_order", "operation", "workstation", "status",
            "production_item", "item_name", "for_quantity", "total_completed_qty",
            "total_time_in_mins", "expected_time_in_mins"
          ]',
          'filters': {'status': 'Work in Progress'},
          'order_by': 'modified desc',
          'limit_page_length': 20,
        },
      );

      if (response.statusCode == 200) {
        final data = response.body['data'] as List;
        activeJobCards.value = data.map((json) => JobCardModel.fromJson(json)).toList();
      }
    } catch (e) {
      if (!silent) {
        GlobalSnackbar.error(message: 'Failed to load active Job Cards: $e');
      }
    }
  }

  /// Fetch Job Card detail
  Future<void> fetchJobCardDetail(String jobCardName) async {
    try {
      isLoadingDetail.value = true;

      final response = await _apiProvider.get('/api/resource/Job Card/$jobCardName');

      if (response.statusCode == 200) {
        selectedJobCard.value = JobCardModel.fromJson(response.body['data']);
        
        // Check if job is in progress
        if (selectedJobCard.value?.status == 'Work in Progress') {
          final timeLogs = selectedJobCard.value?.timeLogs ?? [];
          if (timeLogs.isNotEmpty) {
            final lastLog = timeLogs.last;
            if (lastLog.fromTime != null && lastLog.toTime == null) {
              currentStartTime.value = DateTime.parse(lastLog.fromTime!);
              _startTimeTracking();
            }
          }
        }
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to load Job Card details: $e');
    } finally {
      isLoadingDetail.value = false;
    }
  }

  /// Start Job
  Future<void> startJob(String jobCardName) async {
    try {
      isProcessing.value = true;

      final response = await _apiProvider.post(
        '/api/method/erpnext.manufacturing.doctype.job_card.job_card.make_time_log',
        data: {
          'job_card': jobCardName,
          'from_time': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        GlobalSnackbar.success(message: 'Job started successfully');
        currentStartTime.value = DateTime.now();
        _startTimeTracking();
        await fetchJobCardDetail(jobCardName);
        await fetchActiveJobCards();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to start job: $e');
    } finally {
      isProcessing.value = false;
    }
  }

  /// Complete Job
  Future<void> completeJob(String jobCardName, {double? completedQty}) async {
    try {
      isProcessing.value = true;

      // Validate completed quantity
      final qty = completedQty ?? double.tryParse(completedQtyController.text) ?? 0;
      if (qty <= 0) {
        GlobalSnackbar.error(message: 'Please enter completed quantity');
        return;
      }

      final response = await _apiProvider.post(
        '/api/method/erpnext.manufacturing.doctype.job_card.job_card.make_time_log',
        data: {
          'job_card': jobCardName,
          'to_time': DateTime.now().toIso8601String(),
          'completed_qty': qty,
        },
      );

      if (response.statusCode == 200) {
        GlobalSnackbar.success(message: 'Job completed successfully');
        currentStartTime.value = null;
        _timeTrackingTimer?.cancel();
        elapsedTime.value = '00:00:00';
        completedQtyController.clear();
        await fetchJobCardDetail(jobCardName);
        await fetchActiveJobCards();
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to complete job: $e');
    } finally {
      isProcessing.value = false;
    }
  }

  /// Pause Job (create time log with to_time but keep status as Work in Progress)
  Future<void> pauseJob(String jobCardName) async {
    try {
      isProcessing.value = true;

      final response = await _apiProvider.post(
        '/api/method/erpnext.manufacturing.doctype.job_card.job_card.make_time_log',
        data: {
          'job_card': jobCardName,
          'to_time': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        GlobalSnackbar.success(message: 'Job paused');
        currentStartTime.value = null;
        _timeTrackingTimer?.cancel();
        elapsedTime.value = '00:00:00';
        await fetchJobCardDetail(jobCardName);
      }
    } catch (e) {
      GlobalSnackbar.error(message: 'Failed to pause job: $e');
    } finally {
      isProcessing.value = false;
    }
  }

  /// Set filter status
  void setFilterStatus(String status) {
    filterStatus.value = status;
    fetchJobCardList();
  }

  /// Search Job Card
  void searchJobCard(String query) {
    searchQuery.value = query;
    fetchJobCardList();
  }

  /// Navigate to Job Card detail
  void goToJobCardDetail(String jobCardName) {
    Get.toNamed('/manufacturing/job-card/$jobCardName');
  }

  /// Navigate to active job cards view
  void goToActiveJobCards() {
    Get.toNamed('/manufacturing/job-card-active');
  }
}
