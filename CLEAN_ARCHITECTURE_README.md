# Clean Architecture Implementation

## 🎯 Overview

This project implements **Clean Architecture** for the ddmco_multimax ERPNext mobile app, starting with the Stock Entry module as a reference implementation.

## 📁 Project Structure

```
lib/
├── core/                          # Shared utilities and base classes
│   ├── error/
│   │   ├── failures.dart          # Domain layer errors
│   │   └── exceptions.dart        # Data layer exceptions
│   ├── usecases/
│   │   └── usecase.dart           # Base use case class
│   ├── utils/
│   │   └── either.dart            # Functional error handling
│   └── network/
│       └── network_info.dart      # Network connectivity
│
├── features/                      # Feature modules (clean architecture)
│   └── stock_entry/
│       ├── domain/                # Business logic (pure Dart)
│       │   ├── entities/          # Business objects
│       │   ├── repositories/      # Repository interfaces
│       │   └── usecases/          # Business use cases
│       │
│       ├── data/                  # Data handling
│       │   ├── models/            # DTOs (re-export existing)
│       │   ├── mappers/           # DTO ↔ Entity conversion
│       │   ├── datasources/       # API communication
│       │   └── repositories/      # Repository implementations
│       │
│       └── presentation/          # UI layer
│           ├── controllers/       # State management
│           ├── bindings/          # Dependency injection
│           ├── pages/             # Screens
│           └── widgets/           # UI components
│
└── app/                           # Legacy code (being migrated)
    ├── data/
    ├── modules/
    └── routes/
```

## 🏗️ Architecture Layers

### 1. Domain Layer (Inner Circle)
**Pure business logic - No framework dependencies**

- **Entities**: Core business objects with business rules
- **Repositories**: Interfaces defining data operations
- **Use Cases**: Single-purpose business operations

**Key Principle**: Domain layer knows nothing about UI, databases, or APIs.

### 2. Data Layer (Middle Circle)
**Implements domain contracts**

- **Models**: DTOs for API/database communication
- **Mappers**: Convert between DTOs and Entities
- **Data Sources**: API clients, local databases
- **Repositories**: Implement domain repository interfaces

**Key Principle**: Data layer depends on domain layer, not vice versa.

### 3. Presentation Layer (Outer Circle)
**UI and state management**

- **Controllers**: Manage UI state using use cases
- **Pages**: Flutter screens
- **Widgets**: Reusable UI components
- **Bindings**: Dependency injection setup

**Key Principle**: UI depends on use cases, never directly on data sources.

## 🔄 Data Flow

```
User Interaction
       ↓
   Controller
       ↓
   Use Case (validates business rules)
       ↓
 Repository Interface
       ↓
Repository Implementation (handles errors)
       ↓
   Data Source (API/DB)
       ↓
   External System
```

## ⚡ Quick Start

### For New Developers

1. **Read Documentation**
   - `ARCHITECTURE.md` - Detailed architecture overview
   - `MIGRATION_GUIDE.md` - How to migrate modules
   - `TESTING_GUIDE.md` - Testing strategy

2. **Explore Reference Implementation**
   - Study `lib/features/stock_entry/` thoroughly
   - Understand each layer's responsibility
   - Review the use cases and how they're tested

3. **Run the App**
   ```bash
   flutter pub get
   flutter run
   ```

4. **Run Tests**
   ```bash
   flutter test
   ```

### For Existing Developers

1. **Understand the Shift**
   - Business logic moves to use cases
   - Controllers become thin orchestrators
   - API calls go through repositories

2. **Migration Approach**
   - New features use clean architecture
   - Existing features migrate gradually
   - Both patterns coexist during transition

3. **Key Changes**
   - Controllers inject use cases, not repositories
   - Error handling uses Either<Failure, Success>
   - All async operations return Either

## 📝 Code Examples

### Creating a Use Case

```dart
class GetStockEntries implements UseCase<List<StockEntryEntity>, GetStockEntriesParams> {
  final StockEntryRepository repository;

  GetStockEntries(this.repository);

  @override
  Future<Either<Failure, List<StockEntryEntity>>> call(
    GetStockEntriesParams params,
  ) async {
    // Business validation can go here
    if (params.pageSize > 100) {
      return Either.left(
        ValidationFailure('Page size cannot exceed 100'),
      );
    }

    return await repository.getStockEntries(
      page: params.page,
      pageSize: params.pageSize,
    );
  }
}
```

### Using a Use Case in Controller

```dart
class StockEntryControllerNew extends GetxController {
  final GetStockEntries getStockEntries;

  StockEntryControllerNew({required this.getStockEntries});

  final stockEntries = <StockEntryEntity>[].obs;
  final isLoading = false.obs;

  Future<void> loadStockEntries() async {
    isLoading.value = true;

    final result = await getStockEntries(
      GetStockEntriesParams(page: 1, pageSize: 20),
    );

    result.fold(
      (failure) {
        // Handle error
        Get.snackbar('Error', failure.message);
      },
      (entries) {
        // Handle success
        stockEntries.value = entries;
      },
    );

    isLoading.value = false;
  }
}
```

### Dependency Injection

```dart
class StockEntryBindingNew extends Bindings {
  @override
  void dependencies() {
    // Register dependencies in correct order
    Get.lazyPut<StockEntryRemoteDataSource>(
      () => StockEntryRemoteDataSourceImpl(Get.find()),
    );

    Get.lazyPut<StockEntryRepository>(
      () => StockEntryRepositoryImpl(Get.find()),
    );

    Get.lazyPut(() => GetStockEntries(Get.find()));

    Get.lazyPut(() => StockEntryControllerNew(
      getStockEntries: Get.find(),
    ));
  }
}
```

## ✅ Benefits

1. **Testability**: Each layer can be tested independently with mocks
2. **Maintainability**: Clear separation makes code easier to understand
3. **Scalability**: Adding features doesn't affect existing code
4. **Flexibility**: Can swap UI frameworks without changing business logic
5. **Team Collaboration**: Different teams can work on different layers
6. **Error Handling**: Consistent error handling with Either type
7. **Independence**: Business logic has zero framework dependencies

## 🧪 Testing Strategy

### Unit Tests
- Test each use case independently
- Mock repository dependencies
- Cover all business rules and edge cases

### Integration Tests
- Test complete workflows
- Test error scenarios
- Verify data transformations

### Widget Tests
- Test UI components
- Test user interactions
- Test loading and error states

See `TESTING_GUIDE.md` for detailed testing instructions.

## 🔧 Tools & Dependencies

- **get**: State management and dependency injection
- **dartz**: Functional programming (Either type)
- **equatable**: Value equality for entities
- **dio**: HTTP client
- **mockito**: Mocking for tests
- **build_runner**: Code generation

## 📚 Learning Resources

### Books
- "Clean Architecture" by Robert C. Martin
- "Domain-Driven Design" by Eric Evans

### Articles
- [The Clean Architecture (Uncle Bob)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [Flutter Clean Architecture Guide](https://resocoder.com/flutter-clean-architecture-tdd/)

### Videos
- [Flutter Clean Architecture - Reso Coder](https://www.youtube.com/watch?v=KjE2IDphA_U)
- [SOLID Principles](https://www.youtube.com/watch?v=rtmFCcjEgEw)

## 🚀 Current Status

- ✅ Core layer implemented
- ✅ Stock Entry module (reference implementation)
- ⏳ Testing infrastructure (in progress)
- ⏳ Migration of other modules (planned)

## 📋 Migration Roadmap

### Phase 1: Foundation (Q1 2026) - COMPLETE
- [x] Core layer setup
- [x] Stock Entry reference implementation
- [x] Documentation and guides

### Phase 2: Testing & Refinement (Q2 2026)
- [ ] Unit tests for Stock Entry
- [ ] Integration tests for workflows
- [ ] Widget tests for UI components
- [ ] Performance benchmarks

### Phase 3: Module Migration (Q2-Q3 2026)
- [ ] Delivery Note
- [ ] Purchase Receipt
- [ ] Purchase Order
- [ ] Material Request
- [ ] Other modules

### Phase 4: Cleanup (Q4 2026)
- [ ] Remove legacy code
- [ ] Consolidate patterns
- [ ] Performance optimization
- [ ] Final documentation

## ❓ Troubleshooting

### Common Issues

**Issue**: "GetX dependency not found"
**Solution**: Ensure binding is registered in routes or manually initialize

**Issue**: "Either type not resolved"
**Solution**: Import from `core/utils/either.dart` or use `dartz` package

**Issue**: "API calls failing"
**Solution**: Check ApiProvider is initialized and authenticated

**Issue**: "Tests failing"
**Solution**: Ensure all dependencies are mocked properly

## 👥 Contributing

1. Follow the established patterns in `stock_entry` module
2. Write tests for all new code
3. Update documentation when adding features
4. Get code reviews before merging
5. Keep commits atomic and well-described

## 📞 Support

For questions or issues:
1. Check documentation files first
2. Review reference implementation
3. Discuss with team leads
4. Create detailed issue reports

## 🎓 Best Practices

1. **Keep Domain Pure**: No Flutter imports in domain layer
2. **Single Responsibility**: One use case = one business operation
3. **Dependency Injection**: Always inject dependencies
4. **Error Handling**: Use Either for all async operations
5. **Testing**: Write tests before or during implementation
6. **Documentation**: Comment complex business logic
7. **Naming**: Use clear, descriptive names
8. **Consistency**: Follow established patterns

## 📈 Success Metrics

- Code coverage > 80%
- Build time < 2 minutes
- Zero critical bugs in production
- Developer velocity increase by 30%
- Onboarding time reduced by 50%
- Technical debt score improved by 60%

---

**Last Updated**: March 8, 2026
**Version**: 1.0.0
**Maintainer**: Development Team
