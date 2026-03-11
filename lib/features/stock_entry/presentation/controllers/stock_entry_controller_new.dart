import 'package:get/get.dart';
import '../../../../core/error/failures.dart';
import '../../domain/entities/stock_entry_entity.dart';
import '../../domain/usecases/create_stock_entry.dart';
import '../../domain/usecases/delete_stock_entry.dart';
import '../../domain/usecases/get_stock_entries.dart';
import '../../domain/usecases/get_stock_entry_by_id.dart';
import '../../domain/usecases/submit_stock_entry.dart';
import '../../domain/usecases/update_stock_entry.dart';
import '../../domain/usecases/validate_batch.dart';
import '../../domain/usecases/validate_rack.dart';

/// Refactored Stock Entry Controller using Clean Architecture
/// This is a reference implementation showing how to use use cases
class StockEntryControllerNew extends GetxController {
  final GetStockEntries getStockEntries;
  final GetStockEntryById getStockEntryById;
  final CreateStockEntry createStockEntry;
  final UpdateStockEntry updateStockEntry;
  final SubmitStockEntry submitStockEntry;
  final DeleteStockEntry deleteStockEntry;
  final ValidateRack validateRack;
  final ValidateBatch validateBatch;

  StockEntryControllerNew({
    required this.getStockEntries,
    required this.getStockEntryById,
    required this.createStockEntry,
    required this.updateStockEntry,
    required this.submitStockEntry,
    required this.deleteStockEntry,
    required this.validateRack,
    required this.validateBatch,
  });

  // Reactive state
  final isLoading = false.obs;
  final stockEntries = <StockEntryEntity>[].obs;
  final Rx<StockEntryEntity?> currentStockEntry = Rx<StockEntryEntity?>(null);
  final errorMessage = ''.obs;
  final currentPage = 1.obs;
  final hasMorePages = true.obs;

  @override
  void onInit() {
    super.onInit();
    loadStockEntries();
  }

  /// Load stock entries with pagination
  Future<void> loadStockEntries({
    bool refresh = false,
  }) async {
    if (refresh) {
      currentPage.value = 1;
      stockEntries.clear();
      hasMorePages.value = true;
    }

    if (isLoading.value || !hasMorePages.value) return;

    isLoading.value = true;
    errorMessage.value = '';

    final result = await getStockEntries(
      GetStockEntriesParams(
        page: currentPage.value,
        pageSize: 20,
      ),
    );

    result.fold(
      (failure) {
        errorMessage.value = _mapFailureToMessage(failure);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
        );
      },
      (entries) {
        stockEntries.addAll(entries);
        hasMorePages.value = entries.length == 20;
        currentPage.value++;
      },
    );

    isLoading.value = false;
  }

  /// Load a single stock entry by ID
  Future<void> loadStockEntry(String id) async {
    isLoading.value = true;
    errorMessage.value = '';

    final result = await getStockEntryById(id);

    result.fold(
      (failure) {
        errorMessage.value = _mapFailureToMessage(failure);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
        );
      },
      (stockEntry) {
        currentStockEntry.value = stockEntry;
      },
    );

    isLoading.value = false;
  }

  /// Create a new stock entry
  Future<bool> createNewStockEntry(StockEntryEntity stockEntry) async {
    isLoading.value = true;
    errorMessage.value = '';

    final result = await createStockEntry(stockEntry);

    isLoading.value = false;

    return result.fold(
      (failure) {
        errorMessage.value = _mapFailureToMessage(failure);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
        );
        return false;
      },
      (created) {
        currentStockEntry.value = created;
        Get.snackbar(
          'Success',
          'Stock entry created successfully',
          snackPosition: SnackPosition.BOTTOM,
        );
        return true;
      },
    );
  }

  /// Update an existing stock entry
  Future<bool> updateExistingStockEntry(StockEntryEntity stockEntry) async {
    isLoading.value = true;
    errorMessage.value = '';

    final result = await updateStockEntry(stockEntry);

    isLoading.value = false;

    return result.fold(
      (failure) {
        errorMessage.value = _mapFailureToMessage(failure);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
        );
        return false;
      },
      (updated) {
        currentStockEntry.value = updated;
        Get.snackbar(
          'Success',
          'Stock entry updated successfully',
          snackPosition: SnackPosition.BOTTOM,
        );
        return true;
      },
    );
  }

  /// Submit a stock entry
  Future<bool> submitEntry(String id) async {
    isLoading.value = true;
    errorMessage.value = '';

    final result = await submitStockEntry(id);

    isLoading.value = false;

    return result.fold(
      (failure) {
        errorMessage.value = _mapFailureToMessage(failure);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
        );
        return false;
      },
      (submitted) {
        currentStockEntry.value = submitted;
        Get.snackbar(
          'Success',
          'Stock entry submitted successfully',
          snackPosition: SnackPosition.BOTTOM,
        );
        return true;
      },
    );
  }

  /// Delete a stock entry
  Future<bool> deleteEntry(String id) async {
    isLoading.value = true;
    errorMessage.value = '';

    final result = await deleteStockEntry(id);

    isLoading.value = false;

    return result.fold(
      (failure) {
        errorMessage.value = _mapFailureToMessage(failure);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
        );
        return false;
      },
      (_) {
        stockEntries.removeWhere((entry) => entry.name == id);
        Get.snackbar(
          'Success',
          'Stock entry deleted successfully',
          snackPosition: SnackPosition.BOTTOM,
        );
        return true;
      },
    );
  }

  /// Validate warehouse rack
  Future<bool> checkRackValidity(String warehouse, String rack) async {
    final result = await validateRack(
      ValidateRackParams(warehouse: warehouse, rack: rack),
    );

    return result.fold(
      (failure) {
        Get.snackbar(
          'Validation Error',
          _mapFailureToMessage(failure),
          snackPosition: SnackPosition.BOTTOM,
        );
        return false;
      },
      (isValid) => isValid,
    );
  }

  /// Validate batch
  Future<Map<String, dynamic>?> checkBatchValidity(
    String itemCode,
    String warehouse,
    String batchNo,
  ) async {
    final result = await validateBatch(
      ValidateBatchParams(
        itemCode: itemCode,
        warehouse: warehouse,
        batchNo: batchNo,
      ),
    );

    return result.fold(
      (failure) {
        Get.snackbar(
          'Validation Error',
          _mapFailureToMessage(failure),
          snackPosition: SnackPosition.BOTTOM,
        );
        return null;
      },
      (batchInfo) => batchInfo,
    );
  }

  /// Map failures to user-friendly messages
  String _mapFailureToMessage(Failure failure) {
    switch (failure.runtimeType) {
      case NetworkFailure:
        return 'Network error. Please check your connection.';
      case ServerFailure:
        return failure.message;
      case ValidationFailure:
        return failure.message;
      case AuthFailure:
        return 'Authentication failed. Please login again.';
      case CacheFailure:
        return 'Local data error occurred.';
      default:
        return 'An unexpected error occurred.';
    }
  }
}
