# Testing Guide - Clean Architecture

## Overview

This guide covers testing strategies for the clean architecture implementation, with examples from the Stock Entry module.

## Testing Pyramid

```
        /\
       /  \        E2E Tests (Few)
      /____\
     /      \       Integration Tests (Some)
    /________\
   /          \     Unit Tests (Many)
  /____________\
```

## Test Types

### 1. Unit Tests
Test individual components in isolation with mocked dependencies.

### 2. Integration Tests
Test multiple components working together.

### 3. Widget Tests
Test UI components and user interactions.

### 4. E2E Tests
Test complete user workflows (optional, expensive).

## Setting Up Tests

### Install Dependencies

Already in `pubspec.yaml`:
```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.4
  build_runner: ^2.4.13
```

### Generate Mocks

```bash
flutter pub run build_runner build
```

## Unit Test Examples

### Testing Use Cases

```dart
// test/features/stock_entry/domain/usecases/get_stock_entries_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

@GenerateMocks([StockEntryRepository])
void main() {
  late GetStockEntries useCase;
  late MockStockEntryRepository mockRepository;

  setUp(() {
    mockRepository = MockStockEntryRepository();
    useCase = GetStockEntries(mockRepository);
  });

  group('GetStockEntries', () {
    final tParams = GetStockEntriesParams(
      page: 1,
      pageSize: 20,
    );

    final tStockEntries = [
      StockEntryEntity(
        name: 'STE-001',
        purpose: 'Material Receipt',
        totalAmount: 1000.0,
        postingDate: '2026-03-08',
        modified: '2026-03-08',
        creation: '2026-03-08',
        status: 'Draft',
        docstatus: 0,
        currency: 'AED',
        items: [],
      ),
    ];

    test('should get stock entries from repository', () async {
      // Arrange
      when(mockRepository.getStockEntries(
        page: anyNamed('page'),
        pageSize: anyNamed('pageSize'),
      )).thenAnswer((_) async => Either.right(tStockEntries));

      // Act
      final result = await useCase(tParams);

      // Assert
      expect(result.isRight, true);
      expect(result.rightOrNull, tStockEntries);
      verify(mockRepository.getStockEntries(
        page: tParams.page,
        pageSize: tParams.pageSize,
      ));
      verifyNoMoreInteractions(mockRepository);
    });

    test('should return failure when repository fails', () async {
      // Arrange
      final tFailure = NetworkFailure('No internet connection');
      when(mockRepository.getStockEntries(
        page: anyNamed('page'),
        pageSize: anyNamed('pageSize'),
      )).thenAnswer((_) async => Either.left(tFailure));

      // Act
      final result = await useCase(tParams);

      // Assert
      expect(result.isLeft, true);
      expect(result.leftOrNull, tFailure);
    });
  });
}
```

### Testing Repositories

```dart
// test/features/stock_entry/data/repositories/stock_entry_repository_impl_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';

@GenerateMocks([StockEntryRemoteDataSource])
void main() {
  late StockEntryRepositoryImpl repository;
  late MockStockEntryRemoteDataSource mockRemoteDataSource;

  setUp(() {
    mockRemoteDataSource = MockStockEntryRemoteDataSource();
    repository = StockEntryRepositoryImpl(mockRemoteDataSource);
  });

  group('getStockEntries', () {
    final tStockEntryModels = [
      StockEntry(
        name: 'STE-001',
        purpose: 'Material Receipt',
        totalAmount: 1000.0,
        postingDate: '2026-03-08',
        modified: '2026-03-08',
        creation: '2026-03-08',
        status: 'Draft',
        docstatus: 0,
        currency: 'AED',
        items: [],
      ),
    ];

    test('should return entities when remote call is successful', () async {
      // Arrange
      when(mockRemoteDataSource.getStockEntries(
        page: anyNamed('page'),
        pageSize: anyNamed('pageSize'),
      )).thenAnswer((_) async => tStockEntryModels);

      // Act
      final result = await repository.getStockEntries(
        page: 1,
        pageSize: 20,
      );

      // Assert
      expect(result.isRight, true);
      verify(mockRemoteDataSource.getStockEntries(
        page: 1,
        pageSize: 20,
      ));
    });

    test('should return NetworkFailure when network exception occurs', () async {
      // Arrange
      when(mockRemoteDataSource.getStockEntries(
        page: anyNamed('page'),
        pageSize: anyNamed('pageSize'),
      )).thenThrow(NetworkException('No connection'));

      // Act
      final result = await repository.getStockEntries(
        page: 1,
        pageSize: 20,
      );

      // Assert
      expect(result.isLeft, true);
      expect(result.leftOrNull, isA<NetworkFailure>());
    });

    test('should return ServerFailure when server exception occurs', () async {
      // Arrange
      when(mockRemoteDataSource.getStockEntries(
        page: anyNamed('page'),
        pageSize: anyNamed('pageSize'),
      )).thenThrow(ServerException('Server error', 500));

      // Act
      final result = await repository.getStockEntries(
        page: 1,
        pageSize: 20,
      );

      // Assert
      expect(result.isLeft, true);
      final failure = result.leftOrNull as ServerFailure;
      expect(failure.statusCode, 500);
    });
  });
}
```

### Testing Mappers

```dart
// test/features/stock_entry/data/mappers/stock_entry_mapper_test.dart

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StockEntryMapper', () {
    final tModel = StockEntry(
      name: 'STE-001',
      purpose: 'Material Receipt',
      totalAmount: 1000.0,
      postingDate: '2026-03-08',
      modified: '2026-03-08',
      creation: '2026-03-08',
      status: 'Draft',
      docstatus: 0,
      currency: 'AED',
      items: [],
    );

    test('should convert model to entity correctly', () {
      // Act
      final entity = StockEntryMapper.toEntity(tModel);

      // Assert
      expect(entity.name, tModel.name);
      expect(entity.purpose, tModel.purpose);
      expect(entity.totalAmount, tModel.totalAmount);
      expect(entity.docstatus, tModel.docstatus);
    });

    test('should convert entity to model correctly', () {
      // Arrange
      final entity = StockEntryMapper.toEntity(tModel);

      // Act
      final model = StockEntryMapper.toModel(entity);

      // Assert
      expect(model.name, entity.name);
      expect(model.purpose, entity.purpose);
      expect(model.totalAmount, entity.totalAmount);
    });

    test('should maintain data integrity in round-trip conversion', () {
      // Act
      final entity = StockEntryMapper.toEntity(tModel);
      final modelAgain = StockEntryMapper.toModel(entity);

      // Assert
      expect(modelAgain.name, tModel.name);
      expect(modelAgain.totalAmount, tModel.totalAmount);
    });
  });
}
```

### Testing Controllers

```dart
// test/features/stock_entry/presentation/controllers/stock_entry_controller_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:get/get.dart';

@GenerateMocks([
  GetStockEntries,
  GetStockEntryById,
  CreateStockEntry,
])
void main() {
  late StockEntryControllerNew controller;
  late MockGetStockEntries mockGetStockEntries;
  late MockGetStockEntryById mockGetStockEntryById;
  late MockCreateStockEntry mockCreateStockEntry;

  setUp(() {
    mockGetStockEntries = MockGetStockEntries();
    mockGetStockEntryById = MockGetStockEntryById();
    mockCreateStockEntry = MockCreateStockEntry();

    controller = StockEntryControllerNew(
      getStockEntries: mockGetStockEntries,
      getStockEntryById: mockGetStockEntryById,
      createStockEntry: mockCreateStockEntry,
      updateStockEntry: MockUpdateStockEntry(),
      submitStockEntry: MockSubmitStockEntry(),
      deleteStockEntry: MockDeleteStockEntry(),
      validateRack: MockValidateRack(),
      validateBatch: MockValidateBatch(),
    );
  });

  group('loadStockEntries', () {
    final tStockEntries = [
      StockEntryEntity(
        name: 'STE-001',
        purpose: 'Material Receipt',
        totalAmount: 1000.0,
        postingDate: '2026-03-08',
        modified: '2026-03-08',
        creation: '2026-03-08',
        status: 'Draft',
        docstatus: 0,
        currency: 'AED',
        items: [],
      ),
    ];

    test('should load stock entries successfully', () async {
      // Arrange
      when(mockGetStockEntries(any))
          .thenAnswer((_) async => Either.right(tStockEntries));

      // Act
      await controller.loadStockEntries();

      // Assert
      expect(controller.stockEntries.length, 1);
      expect(controller.isLoading.value, false);
      expect(controller.errorMessage.value, '');
    });

    test('should set error message when loading fails', () async {
      // Arrange
      final tFailure = NetworkFailure('No connection');
      when(mockGetStockEntries(any))
          .thenAnswer((_) async => Either.left(tFailure));

      // Act
      await controller.loadStockEntries();

      // Assert
      expect(controller.stockEntries.isEmpty, true);
      expect(controller.isLoading.value, false);
      expect(controller.errorMessage.value, isNotEmpty);
    });
  });
}
```

## Widget Test Examples

```dart
// test/features/stock_entry/presentation/pages/stock_entry_list_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('should display loading indicator when loading', (tester) async {
    // Arrange
    final controller = StockEntryControllerNew(
      // ... inject mocked use cases
    );
    controller.isLoading.value = true;
    Get.put(controller);

    // Act
    await tester.pumpWidget(
      GetMaterialApp(
        home: StockEntryListPage(),
      ),
    );

    // Assert
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('should display stock entries when loaded', (tester) async {
    // Arrange
    final controller = StockEntryControllerNew(
      // ... inject mocked use cases
    );
    controller.stockEntries.value = [
      // ... test data
    ];
    Get.put(controller);

    // Act
    await tester.pumpWidget(
      GetMaterialApp(
        home: StockEntryListPage(),
      ),
    );
    await tester.pumpAndSettle();

    // Assert
    expect(find.byType(ListTile), findsWidgets);
  });
}
```

## Integration Test Examples

```dart
// integration_test/stock_entry_workflow_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Stock Entry Workflow', () {
    testWidgets('complete create and submit workflow', (tester) async {
      // Launch app
      await tester.pumpWidget(MyApp());
      await tester.pumpAndSettle();

      // Navigate to stock entry
      await tester.tap(find.text('Stock Entry'));
      await tester.pumpAndSettle();

      // Create new entry
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // Fill form
      await tester.enterText(find.byKey(Key('reference_no')), 'TEST-001');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Verify success
      expect(find.text('Stock entry created'), findsOneWidget);
    });
  });
}
```

## Test Coverage

### Generate Coverage Report

```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Coverage Goals

- **Domain Layer**: 100% (pure logic, easy to test)
- **Data Layer**: 90%+ (focus on error handling)
- **Presentation Layer**: 70%+ (UI is harder to test)
- **Overall**: 80%+

## Continuous Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage
      - uses: codecov/codecov-action@v3
```

## Best Practices

1. **AAA Pattern**: Arrange, Act, Assert
2. **One Assertion**: Focus each test on one thing
3. **Mock External Dependencies**: Only test your code
4. **Use Descriptive Names**: Test names should explain what they test
5. **Test Edge Cases**: Don't just test happy paths
6. **Keep Tests Fast**: Unit tests should run in milliseconds
7. **Isolate Tests**: Each test should be independent
8. **Use Test Data Builders**: Create reusable test data

## Common Pitfalls

1. **Over-mocking**: Don't mock what you don't need to
2. **Testing Implementation**: Test behavior, not implementation
3. **Brittle Tests**: Don't couple tests to internal structure
4. **Slow Tests**: Keep unit tests fast
5. **No Negative Tests**: Test failure scenarios too
6. **Ignoring Coverage**: Aim for high coverage

## Resources

- [Flutter Testing Documentation](https://flutter.dev/docs/testing)
- [Mockito Documentation](https://pub.dev/packages/mockito)
- [Test-Driven Development](https://en.wikipedia.org/wiki/Test-driven_development)

---

**Remember**: Tests are as important as production code. Write them first or alongside your implementation.
