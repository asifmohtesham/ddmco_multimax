import 'package:get/get.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/item_entity.dart';
import '../../domain/usecases/get_items.dart';
import '../../domain/usecases/get_item_by_code.dart';
import '../../domain/usecases/get_item_groups.dart';
import '../../domain/usecases/get_template_items.dart';
import '../../domain/usecases/get_item_attributes.dart';
import '../../domain/usecases/get_stock_levels.dart';
import '../../domain/usecases/get_warehouse_stock.dart';
import '../../domain/usecases/get_stock_ledger.dart';

/// Refactored Item Controller using Clean Architecture
/// Depends only on use cases, not data sources or repositories
class ItemControllerNew extends GetxController {
  final GetItems getItems;
  final GetItemByCode getItemByCode;
  final GetItemGroups getItemGroups;
  final GetTemplateItems getTemplateItems;
  final GetItemAttributes getItemAttributes;
  final GetStockLevels getStockLevels;
  final GetWarehouseStock getWarehouseStock;
  final GetStockLedger getStockLedger;

  ItemControllerNew({
    required this.getItems,
    required this.getItemByCode,
    required this.getItemGroups,
    required this.getTemplateItems,
    required this.getItemAttributes,
    required this.getStockLevels,
    required this.getWarehouseStock,
    required this.getStockLedger,
  });

  // Reactive state
  final isLoading = false.obs;
  final items = <ItemEntity>[].obs;
  final Rx<ItemEntity?> currentItem = Rx<ItemEntity?>(null);
  final itemGroups = <String>[].obs;
  final templateItems = <String>[].obs;
  final itemAttributes = <String>[].obs;
  final stockLevels = <WarehouseStockEntity>[].obs;
  final stockLedger = <StockLedgerEntity>[].obs;
  final errorMessage = ''.obs;
  final currentPage = 1.obs;
  final hasMorePages = true.obs;

  // Filters
  final selectedItemGroup = Rx<String?>(null);
  final searchQuery = ''.obs;
  final selectedFilters = <List<dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    loadItems();
    loadItemGroups();
  }

  /// Load items with pagination and filters
  Future<void> loadItems({
    bool refresh = false,
  }) async {
    if (refresh) {
      currentPage.value = 1;
      items.clear();
      hasMorePages.value = true;
    }

    if (isLoading.value || !hasMorePages.value) return;

    isLoading.value = true;
    errorMessage.value = '';

    // Build filters
    final filters = <List<dynamic>>[];
    if (selectedItemGroup.value != null) {
      filters.add(['item_group', '=', selectedItemGroup.value!]);
    }
    if (searchQuery.value.isNotEmpty) {
      filters.add(['item_name', 'like', '%${searchQuery.value}%']);
    }
    filters.addAll(selectedFilters);

    final result = await getItems(
      GetItemsParams(
        page: currentPage.value,
        pageSize: 20,
        filters: filters.isNotEmpty ? filters : null,
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
      (newItems) {
        items.addAll(newItems);
        hasMorePages.value = newItems.length == 20;
        currentPage.value++;
      },
    );

    isLoading.value = false;
  }

  /// Load a single item by code
  Future<void> loadItemByCode(String itemCode) async {
    isLoading.value = true;
    errorMessage.value = '';

    final result = await getItemByCode(itemCode);

    result.fold(
      (failure) {
        errorMessage.value = _mapFailureToMessage(failure);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
        );
      },
      (item) {
        currentItem.value = item;
      },
    );

    isLoading.value = false;
  }

  /// Load all item groups
  Future<void> loadItemGroups() async {
    final result = await getItemGroups(NoParams());

    result.fold(
      (failure) {
        // Silently fail for background data
      },
      (groups) {
        itemGroups.value = groups;
      },
    );
  }

  /// Load template items
  Future<void> loadTemplateItems() async {
    final result = await getTemplateItems(NoParams());

    result.fold(
      (failure) {
        Get.snackbar(
          'Error',
          _mapFailureToMessage(failure),
          snackPosition: SnackPosition.BOTTOM,
        );
      },
      (templates) {
        templateItems.value = templates;
      },
    );
  }

  /// Load item attributes
  Future<void> loadItemAttributes() async {
    final result = await getItemAttributes(NoParams());

    result.fold(
      (failure) {
        Get.snackbar(
          'Error',
          _mapFailureToMessage(failure),
          snackPosition: SnackPosition.BOTTOM,
        );
      },
      (attributes) {
        itemAttributes.value = attributes;
      },
    );
  }

  /// Load stock levels for an item
  Future<void> loadStockLevels(String itemCode) async {
    isLoading.value = true;
    stockLevels.clear();

    final result = await getStockLevels(itemCode);

    result.fold(
      (failure) {
        errorMessage.value = _mapFailureToMessage(failure);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
        );
      },
      (levels) {
        stockLevels.value = levels;
      },
    );

    isLoading.value = false;
  }

  /// Load warehouse stock
  Future<void> loadWarehouseStock(String warehouse) async {
    isLoading.value = true;
    stockLevels.clear();

    final result = await getWarehouseStock(warehouse);

    result.fold(
      (failure) {
        errorMessage.value = _mapFailureToMessage(failure);
        Get.snackbar(
          'Error',
          errorMessage.value,
          snackPosition: SnackPosition.BOTTOM,
        );
      },
      (stocks) {
        stockLevels.value = stocks;
      },
    );

    isLoading.value = false;
  }

  /// Load stock ledger for an item
  Future<void> loadStockLedger(
    String itemCode, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    isLoading.value = true;
    stockLedger.clear();

    final result = await getStockLedger(
      GetStockLedgerParams(
        itemCode: itemCode,
        fromDate: fromDate,
        toDate: toDate,
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
      (ledger) {
        stockLedger.value = ledger;
      },
    );

    isLoading.value = false;
  }

  /// Set item group filter
  void setItemGroupFilter(String? group) {
    selectedItemGroup.value = group;
    loadItems(refresh: true);
  }

  /// Set search query
  void setSearchQuery(String query) {
    searchQuery.value = query;
    loadItems(refresh: true);
  }

  /// Clear all filters
  void clearFilters() {
    selectedItemGroup.value = null;
    searchQuery.value = '';
    selectedFilters.clear();
    loadItems(refresh: true);
  }

  /// Get total stock for current item
  double get totalStock {
    return stockLevels.fold(0.0, (sum, stock) => sum + stock.quantity);
  }

  /// Get available warehouses count
  int get availableWarehousesCount {
    return stockLevels.where((stock) => stock.hasStock).length;
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
