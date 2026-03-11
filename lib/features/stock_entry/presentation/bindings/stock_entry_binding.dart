import 'package:get/get.dart';
import '../../../../app/data/providers/api_provider.dart';
import '../../data/datasources/stock_entry_remote_data_source.dart';
import '../../data/datasources/stock_entry_remote_data_source_impl.dart';
import '../../data/repositories/stock_entry_repository_impl.dart';
import '../../domain/repositories/stock_entry_repository.dart';
import '../../domain/usecases/create_stock_entry.dart';
import '../../domain/usecases/delete_stock_entry.dart';
import '../../domain/usecases/get_stock_entries.dart';
import '../../domain/usecases/get_stock_entry_by_id.dart';
import '../../domain/usecases/submit_stock_entry.dart';
import '../../domain/usecases/update_stock_entry.dart';
import '../../domain/usecases/validate_batch.dart';
import '../../domain/usecases/validate_rack.dart';
import '../controllers/stock_entry_controller_new.dart';

/// Dependency injection binding for Stock Entry module
/// This sets up the complete dependency graph following clean architecture
class StockEntryBindingNew extends Bindings {
  @override
  void dependencies() {
    // ApiProvider should already be available globally
    // If not, you can inject it here:
    // Get.lazyPut<ApiProvider>(() => ApiProvider());

    // Data Sources
    Get.lazyPut<StockEntryRemoteDataSource>(
      () => StockEntryRemoteDataSourceImpl(Get.find<ApiProvider>()),
    );

    // Repositories
    Get.lazyPut<StockEntryRepository>(
      () => StockEntryRepositoryImpl(Get.find<StockEntryRemoteDataSource>()),
    );

    // Use Cases
    Get.lazyPut(() => GetStockEntries(Get.find<StockEntryRepository>()));
    Get.lazyPut(() => GetStockEntryById(Get.find<StockEntryRepository>()));
    Get.lazyPut(() => CreateStockEntry(Get.find<StockEntryRepository>()));
    Get.lazyPut(() => UpdateStockEntry(Get.find<StockEntryRepository>()));
    Get.lazyPut(() => SubmitStockEntry(Get.find<StockEntryRepository>()));
    Get.lazyPut(() => DeleteStockEntry(Get.find<StockEntryRepository>()));
    Get.lazyPut(() => ValidateRack(Get.find<StockEntryRepository>()));
    Get.lazyPut(() => ValidateBatch(Get.find<StockEntryRepository>()));

    // Controller
    Get.lazyPut<StockEntryControllerNew>(
      () => StockEntryControllerNew(
        getStockEntries: Get.find<GetStockEntries>(),
        getStockEntryById: Get.find<GetStockEntryById>(),
        createStockEntry: Get.find<CreateStockEntry>(),
        updateStockEntry: Get.find<UpdateStockEntry>(),
        submitStockEntry: Get.find<SubmitStockEntry>(),
        deleteStockEntry: Get.find<DeleteStockEntry>(),
        validateRack: Get.find<ValidateRack>(),
        validateBatch: Get.find<ValidateBatch>(),
      ),
    );
  }
}
