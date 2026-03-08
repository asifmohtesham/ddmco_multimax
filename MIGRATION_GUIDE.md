# Migration Guide: Clean Architecture Implementation

## Overview

This guide explains how to gradually migrate existing modules to clean architecture, using Stock Entry as the reference implementation.

## Migration Strategy

### Phase 1: Coexistence (Current)

- New clean architecture code lives alongside existing code
- Both old and new controllers can coexist
- Gradual feature-by-feature migration
- Zero disruption to existing functionality

### Phase 2: Transition

- Update routes to use new bindings
- Replace old controllers with new ones
- Update UI to consume new controller API
- Run parallel tests to ensure parity

### Phase 3: Cleanup

- Remove old implementation files
- Clean up unused dependencies
- Consolidate duplicate code

## Step-by-Step Migration

### Step 1: Create Domain Layer

1. **Create Entities** (`domain/entities/`)
   ```dart
   // Example: Purchase Order Entity
   class PurchaseOrderEntity extends Equatable {
     final String name;
     final String supplier;
     final double totalAmount;
     final List<PurchaseOrderItemEntity> items;

     // Business logic methods
     bool get canBeSubmitted => items.isNotEmpty && totalAmount > 0;
   }
   ```

2. **Define Repository Interface** (`domain/repositories/`)
   ```dart
   abstract class PurchaseOrderRepository {
     Future<Either<Failure, List<PurchaseOrderEntity>>> getPurchaseOrders();
     Future<Either<Failure, PurchaseOrderEntity>> getPurchaseOrderById(String id);
     // ... other operations
   }
   ```

3. **Create Use Cases** (`domain/usecases/`)
   ```dart
   class GetPurchaseOrders implements UseCase<List<PurchaseOrderEntity>, GetPurchaseOrdersParams> {
     final PurchaseOrderRepository repository;

     GetPurchaseOrders(this.repository);

     @override
     Future<Either<Failure, List<PurchaseOrderEntity>>> call(params) {
       // Add business validation if needed
       return repository.getPurchaseOrders(/* params */);
     }
   }
   ```

### Step 2: Implement Data Layer

1. **Create Mappers** (`data/mappers/`)
   ```dart
   class PurchaseOrderMapper {
     static PurchaseOrderEntity toEntity(PurchaseOrder model) {
       return PurchaseOrderEntity(
         name: model.name,
         supplier: model.supplier,
         // ... map all fields
       );
     }

     static PurchaseOrder toModel(PurchaseOrderEntity entity) {
       // Reverse mapping
     }
   }
   ```

2. **Create Data Source Interface** (`data/datasources/`)
   ```dart
   abstract class PurchaseOrderRemoteDataSource {
     Future<List<PurchaseOrder>> getPurchaseOrders();
     Future<PurchaseOrder> getPurchaseOrderById(String id);
     // Throws exceptions, not failures
   }
   ```

3. **Implement Data Source** (`data/datasources/`)
   ```dart
   class PurchaseOrderRemoteDataSourceImpl implements PurchaseOrderRemoteDataSource {
     final ApiProvider apiProvider;

     @override
     Future<List<PurchaseOrder>> getPurchaseOrders() async {
       try {
         final response = await apiProvider.dio.get('/api/resource/Purchase Order');
         // Parse and return
       } on DioException catch (e) {
         throw _handleDioError(e);
       }
     }
   }
   ```

4. **Implement Repository** (`data/repositories/`)
   ```dart
   class PurchaseOrderRepositoryImpl implements PurchaseOrderRepository {
     final PurchaseOrderRemoteDataSource remoteDataSource;

     @override
     Future<Either<Failure, List<PurchaseOrderEntity>>> getPurchaseOrders() async {
       try {
         final models = await remoteDataSource.getPurchaseOrders();
         return Either.right(PurchaseOrderMapper.toEntityList(models));
       } on NetworkException catch (e) {
         return Either.left(NetworkFailure(e.message));
       } on ServerException catch (e) {
         return Either.left(ServerFailure(e.message, e.statusCode));
       }
     }
   }
   ```

### Step 3: Refactor Presentation Layer

1. **Create New Controller** (`presentation/controllers/`)
   ```dart
   class PurchaseOrderControllerNew extends GetxController {
     final GetPurchaseOrders getPurchaseOrders;
     final CreatePurchaseOrder createPurchaseOrder;
     // ... inject all use cases

     final purchaseOrders = <PurchaseOrderEntity>[].obs;
     final isLoading = false.obs;

     Future<void> loadPurchaseOrders() async {
       isLoading.value = true;
       final result = await getPurchaseOrders(GetPurchaseOrdersParams());
       result.fold(
         (failure) => _handleError(failure),
         (orders) => purchaseOrders.value = orders,
       );
       isLoading.value = false;
     }
   }
   ```

2. **Create Binding** (`presentation/bindings/`)
   ```dart
   class PurchaseOrderBindingNew extends Bindings {
     @override
     void dependencies() {
       // Data Sources
       Get.lazyPut<PurchaseOrderRemoteDataSource>(
         () => PurchaseOrderRemoteDataSourceImpl(Get.find()),
       );

       // Repositories
       Get.lazyPut<PurchaseOrderRepository>(
         () => PurchaseOrderRepositoryImpl(Get.find()),
       );

       // Use Cases
       Get.lazyPut(() => GetPurchaseOrders(Get.find()));
       Get.lazyPut(() => CreatePurchaseOrder(Get.find()));

       // Controller
       Get.lazyPut(() => PurchaseOrderControllerNew(
         getPurchaseOrders: Get.find(),
         createPurchaseOrder: Get.find(),
       ));
     }
   }
   ```

3. **Update Routes** (when ready to switch)
   ```dart
   GetPage(
     name: '/purchase-order',
     page: () => PurchaseOrderScreen(),
     binding: PurchaseOrderBindingNew(), // Use new binding
   )
   ```

### Step 4: Update UI

1. **Update GetX bindings in widgets**
   ```dart
   // Old
   final controller = Get.find<PurchaseOrderController>();

   // New (when ready)
   final controller = Get.find<PurchaseOrderControllerNew>();
   ```

2. **Adapt to new controller API**
   - Controllers now return `Either<Failure, Success>`
   - Error handling is standardized
   - Loading states are consistent

### Step 5: Add Tests

1. **Unit Tests for Use Cases**
   ```dart
   void main() {
     late GetPurchaseOrders useCase;
     late MockPurchaseOrderRepository mockRepository;

     setUp(() {
       mockRepository = MockPurchaseOrderRepository();
       useCase = GetPurchaseOrders(mockRepository);
     });

     test('should get purchase orders from repository', () async {
       // Arrange
       when(mockRepository.getPurchaseOrders())
           .thenAnswer((_) async => Right(tPurchaseOrderList));

       // Act
       final result = await useCase(GetPurchaseOrdersParams());

       // Assert
       expect(result, Right(tPurchaseOrderList));
       verify(mockRepository.getPurchaseOrders());
     });
   }
   ```

2. **Integration Tests**
   ```dart
   testWidgets('should display purchase orders', (tester) async {
     // Arrange
     await tester.pumpWidget(MyApp());
     await tester.tap(find.text('Purchase Orders'));
     await tester.pumpAndSettle();

     // Assert
     expect(find.byType(PurchaseOrderListItem), findsWidgets);
   });
   ```

## Common Patterns

### Pattern 1: Paginated Lists

```dart
class GetStockEntriesParams {
  final int page;
  final int pageSize;
  final String? searchQuery;
  final Map<String, dynamic>? filters;
}
```

### Pattern 2: Single Item Fetch

```dart
class GetStockEntryById implements UseCase<StockEntryEntity, String> {
  @override
  Future<Either<Failure, StockEntryEntity>> call(String id) async {
    return await repository.getStockEntryById(id);
  }
}
```

### Pattern 3: Validation Use Cases

```dart
class ValidateRack implements UseCase<bool, ValidateRackParams> {
  @override
  Future<Either<Failure, bool>> call(ValidateRackParams params) async {
    return await repository.validateRack(
      warehouse: params.warehouse,
      rack: params.rack,
    );
  }
}
```

### Pattern 4: Complex Operations

```dart
class SubmitStockEntry implements UseCase<StockEntryEntity, String> {
  @override
  Future<Either<Failure, StockEntryEntity>> call(String id) async {
    // Can add pre-submission validation here
    return await repository.submitStockEntry(id);
  }
}
```

## Checklist for Each Module

- [ ] Domain entities created
- [ ] Repository interface defined
- [ ] All use cases implemented
- [ ] Mappers created
- [ ] Remote data source interface and implementation
- [ ] Repository implementation with error handling
- [ ] New controller with use case dependencies
- [ ] Dependency injection binding
- [ ] Unit tests for use cases
- [ ] Integration tests for workflows
- [ ] UI updated to use new controller
- [ ] Routes updated to use new binding
- [ ] Old code removed (after verification)
- [ ] Documentation updated

## Testing During Migration

1. **Parallel Running**: Keep both old and new implementations
2. **Feature Flags**: Use flags to switch between implementations
3. **Incremental Rollout**: Migrate one screen at a time
4. **Regression Testing**: Ensure existing features still work
5. **User Testing**: Beta test with internal users first

## Rollback Plan

 If issues arise during migration:

1. Keep old implementation files intact until fully verified
2. Use Git branches for migration work
3. Feature flags allow instant rollback
4. Document any breaking changes

## Priority Order for Module Migration

1. ✅ **Stock Entry** (Complete - Reference Implementation)
2. **Delivery Note** (High Priority)
3. **Purchase Receipt** (High Priority)
4. **Purchase Order** (Medium Priority)
5. **Material Request** (Medium Priority)
6. **Packing Slip** (Medium Priority)
7. **Work Order** (Low Priority)
8. **Job Card** (Low Priority)
9. **BOM** (Low Priority)

## Best Practices

1. **One Module at a Time**: Don't rush
2. **Test Thoroughly**: Add tests before migration
3. **Document Changes**: Update architecture docs
4. **Team Review**: Get code reviews from peers
5. **User Feedback**: Involve stakeholders early
6. **Performance**: Monitor app performance
7. **Error Tracking**: Use crash reporting tools

## Common Pitfalls to Avoid

1. **Over-engineering**: Keep it simple, don't add unnecessary abstractions
2. **Mixing Layers**: Ensure strict layer separation
3. **Direct API Calls**: Always go through use cases
4. **Ignoring Tests**: Write tests as you migrate
5. **Big Bang Migration**: Migrate incrementally
6. **Breaking Changes**: Maintain backward compatibility during transition

## Questions & Support

Refer to:
- `ARCHITECTURE.md` for architecture overview
- `lib/features/stock_entry/` for reference implementation
- Code comments for specific patterns
- Team discussions for complex scenarios

## Success Metrics

- Code coverage > 80%
- Zero regressions in existing features
- Improved maintainability scores
- Faster feature development
- Reduced bug count
- Better team velocity
