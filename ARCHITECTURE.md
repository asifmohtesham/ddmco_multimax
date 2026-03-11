# Clean Architecture Implementation - Stock Entry Module

## Overview

This document describes the clean architecture implementation for the Stock Entry module in the ddmco_multimax ERPNext mobile app. This serves as a reference implementation for migrating other modules.

## Architecture Layers

### 1. Core Layer (`lib/core/`)

Contains shared utilities and base classes used across all features.

#### Components:
- **error/**: Exception and Failure classes
  - `failures.dart`: Base Failure classes (NetworkFailure, ServerFailure, etc.)
  - `exceptions.dart`: Exception classes thrown by data layer
- **usecases/**: Base UseCase abstract class
- **utils/**: Utility classes like Either type
- **network/**: Network connectivity checker interface

### 2. Features Layer (`lib/features/stock_entry/`)

Organized by feature, following clean architecture principles.

#### Domain Layer (`domain/`)
**Pure business logic with zero dependencies on frameworks or external packages.**

- **entities/**: Business objects
  - `stock_entry_entity.dart`: Core domain models
  - Contains business rules and validations
  - Immutable and framework-independent

- **repositories/**: Repository interfaces
  - `stock_entry_repository.dart`: Contract for data operations
  - Defines what operations are available
  - No implementation details

- **usecases/**: Business use cases
  - `get_stock_entries.dart`: Fetch paginated list
  - `get_stock_entry_by_id.dart`: Fetch single entry
  - `create_stock_entry.dart`: Create new entry with validation
  - `update_stock_entry.dart`: Update existing entry
  - `submit_stock_entry.dart`: Submit for approval
  - `delete_stock_entry.dart`: Delete entry
  - `validate_rack.dart`: Validate warehouse rack
  - `validate_batch.dart`: Validate batch availability
  - Each use case encapsulates a single business operation

#### Data Layer (`data/`)
**Implements domain contracts and handles external data sources.**

- **models/**: Data Transfer Objects (DTOs)
  - Re-exports existing models from `app/data/models/`
  - Maintains backward compatibility

- **mappers/**: Convert between DTOs and Entities
  - `stock_entry_mapper.dart`: Bidirectional conversion
  - Keeps domain layer clean from JSON/API concerns

- **datasources/**: External data source interfaces and implementations
  - `stock_entry_remote_data_source.dart`: Interface
  - `stock_entry_remote_data_source_impl.dart`: API implementation
  - Wraps existing ApiProvider
  - Throws exceptions on errors

- **repositories/**: Repository implementations
  - `stock_entry_repository_impl.dart`: Implements domain repository
  - Coordinates data sources
  - Converts exceptions to failures
  - Returns Either<Failure, Data> for functional error handling

#### Presentation Layer (`presentation/`)
**UI components using clean architecture patterns.**

- **controllers/**: State management with use cases
  - `stock_entry_controller_new.dart`: Refactored controller
  - Depends only on use cases
  - No direct API calls
  - Handles UI state and user interactions

- **bindings/**: Dependency injection
  - `stock_entry_binding.dart`: GetX binding
  - Sets up entire dependency graph
  - Lazy initialization of dependencies

- **pages/**: UI screens (to be migrated)
- **widgets/**: Reusable UI components (to be migrated)

## Data Flow

```
UI (Widget)
    ↓
Controller
    ↓
Use Case (Business Logic)
    ↓
Repository Interface
    ↓
Repository Implementation
    ↓
Data Source
    ↓
API / Database
```

## Error Handling Strategy

### Exceptions (Data Layer)
Thrown by data sources when operations fail:
- `NetworkException`: Connection issues
- `ServerException`: API errors
- `CacheException`: Local storage errors
- `ValidationException`: Data validation failures
- `AuthException`: Authentication failures

### Failures (Domain Layer)
Returned as Either<Failure, Success>:
- `NetworkFailure`: Network-related issues
- `ServerFailure`: Server errors with status codes
- `CacheFailure`: Local data issues
- `ValidationFailure`: Business rule violations
- `AuthFailure`: Authentication/authorization failures
- `UnexpectedFailure`: Unknown errors

### Either Type
Functional approach to error handling:
```dart
Either<Failure, StockEntryEntity> result = await useCase(params);

result.fold(
  (failure) => handleError(failure),
  (success) => handleSuccess(success),
);
```

## Dependency Injection

Using GetX for dependency injection:

```dart
class StockEntryBindingNew extends Bindings {
  @override
  void dependencies() {
    // Data Sources
    Get.lazyPut<StockEntryRemoteDataSource>(
      () => StockEntryRemoteDataSourceImpl(Get.find<ApiProvider>()),
    );

    // Repositories
    Get.lazyPut<StockEntryRepository>(
      () => StockEntryRepositoryImpl(Get.find()),
    );

    // Use Cases
    Get.lazyPut(() => GetStockEntries(Get.find()));
    Get.lazyPut(() => CreateStockEntry(Get.find()));
    // ... more use cases

    // Controller
    Get.lazyPut(() => StockEntryControllerNew(
      getStockEntries: Get.find(),
      createStockEntry: Get.find(),
      // ... inject use cases
    ));
  }
}
```

## Testing Strategy

### Unit Tests
- **Entities**: Test business rules and validations
- **Use Cases**: Test business logic in isolation
- **Repositories**: Test error handling and data transformation
- **Mappers**: Test bidirectional conversion accuracy

### Integration Tests
- Test complete workflows from controller to API
- Test error scenarios and recovery
- Test offline capabilities

### Widget Tests
- Test UI components in isolation
- Test user interactions
- Test loading and error states

## Migration Guide

See `MIGRATION_GUIDE.md` for step-by-step instructions on migrating other modules.

## Benefits

1. **Testability**: Each layer can be tested independently
2. **Maintainability**: Clear separation of concerns
3. **Scalability**: Easy to add new features
4. **Flexibility**: Can change UI framework without affecting business logic
5. **Team Collaboration**: Different teams can work on different layers
6. **Error Handling**: Consistent error handling across the app
7. **Code Reusability**: Use cases can be shared across different UI implementations

## Key Principles

1. **Dependency Rule**: Dependencies point inward (UI → Use Cases → Entities)
2. **Independence**: Domain layer has no external dependencies
3. **Single Responsibility**: Each class has one reason to change
4. **Interface Segregation**: Depend on abstractions, not concretions
5. **Inversion of Control**: High-level modules don't depend on low-level modules

## Next Steps

1. Add comprehensive unit tests for Stock Entry use cases
2. Migrate UI components to use new controller
3. Add integration tests for complete workflows
4. Implement offline capability with local data source
5. Migrate other modules using this pattern
6. Add logging and analytics
7. Implement caching strategy

## Questions?

Refer to the code comments and this documentation. For complex scenarios, discuss with the team before implementation.
