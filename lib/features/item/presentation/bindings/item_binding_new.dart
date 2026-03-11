import 'package:get/get.dart';
import '../../../../app/data/providers/item_provider.dart';
import '../../data/datasources/item_remote_data_source.dart';
import '../../data/datasources/item_remote_data_source_impl.dart';
import '../../data/repositories/item_repository_impl.dart';
import '../../domain/repositories/item_repository.dart';
import '../../domain/usecases/get_items.dart';
import '../../domain/usecases/get_item_by_code.dart';
import '../../domain/usecases/get_item_groups.dart';
import '../../domain/usecases/get_template_items.dart';
import '../../domain/usecases/get_item_attributes.dart';
import '../../domain/usecases/get_stock_levels.dart';
import '../../domain/usecases/get_warehouse_stock.dart';
import '../../domain/usecases/get_stock_ledger.dart';
import '../controllers/item_controller_new.dart';

/// Dependency injection binding for Item module
/// Sets up the complete dependency graph following clean architecture
class ItemBindingNew extends Bindings {
  @override
  void dependencies() {
    // ItemProvider should already be available
    // If not, register it:
    // Get.lazyPut<ItemProvider>(() => ItemProvider());

    // Data Sources
    Get.lazyPut<ItemRemoteDataSource>(
      () => ItemRemoteDataSourceImpl(Get.find<ItemProvider>()),
    );

    // Repositories
    Get.lazyPut<ItemRepository>(
      () => ItemRepositoryImpl(Get.find<ItemRemoteDataSource>()),
    );

    // Use Cases
    Get.lazyPut(() => GetItems(Get.find<ItemRepository>()));
    Get.lazyPut(() => GetItemByCode(Get.find<ItemRepository>()));
    Get.lazyPut(() => GetItemGroups(Get.find<ItemRepository>()));
    Get.lazyPut(() => GetTemplateItems(Get.find<ItemRepository>()));
    Get.lazyPut(() => GetItemAttributes(Get.find<ItemRepository>()));
    Get.lazyPut(() => GetStockLevels(Get.find<ItemRepository>()));
    Get.lazyPut(() => GetWarehouseStock(Get.find<ItemRepository>()));
    Get.lazyPut(() => GetStockLedger(Get.find<ItemRepository>()));

    // Controller
    Get.lazyPut<ItemControllerNew>(
      () => ItemControllerNew(
        getItems: Get.find<GetItems>(),
        getItemByCode: Get.find<GetItemByCode>(),
        getItemGroups: Get.find<GetItemGroups>(),
        getTemplateItems: Get.find<GetTemplateItems>(),
        getItemAttributes: Get.find<GetItemAttributes>(),
        getStockLevels: Get.find<GetStockLevels>(),
        getWarehouseStock: Get.find<GetWarehouseStock>(),
        getStockLedger: Get.find<GetStockLedger>(),
      ),
    );
  }
}
