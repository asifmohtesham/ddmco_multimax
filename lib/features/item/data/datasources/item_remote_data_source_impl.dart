import 'package:dio/dio.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../app/data/providers/item_provider.dart';
import '../../../../app/data/models/item_model.dart';
import 'item_remote_data_source.dart';

/// Implementation of ItemRemoteDataSource using existing ItemProvider
class ItemRemoteDataSourceImpl implements ItemRemoteDataSource {
  final ItemProvider itemProvider;

  ItemRemoteDataSourceImpl(this.itemProvider);

  @override
  Future<List<Item>> getItems({
    required int page,
    required int pageSize,
    List<List<dynamic>>? filters,
    String? orderBy,
  }) async {
    try {
      final limitStart = (page - 1) * pageSize;
      final response = await itemProvider.getItems(
        limit: pageSize,
        limitStart: limitStart,
        filters: filters,
        orderBy: orderBy ?? '`tabItem`.`modified` desc',
      );

      final List<dynamic> data = response['data'] ?? [];
      return data.map((json) => Item.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Failed to fetch items: $e');
    }
  }

  @override
  Future<Item> getItemByCode(String itemCode) async {
    try {
      final response = await itemProvider.getItems(
        limit: 1,
        limitStart: 0,
        filters: [['item_code', '=', itemCode]],
      );

      final List<dynamic> data = response['data'] ?? [];
      if (data.isEmpty) {
        throw ServerException('Item not found: $itemCode', 404);
      }

      return Item.fromJson(data.first);
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch item: $e');
    }
  }

  @override
  Future<List<String>> getItemGroups() async {
    try {
      final response = await itemProvider.getItemGroups();

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.map((item) => item['name'] as String).toList();
      } else {
        throw ServerException(
          'Failed to fetch item groups',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch item groups: $e');
    }
  }

  @override
  Future<List<String>> getTemplateItems() async {
    try {
      final response = await itemProvider.getTemplateItems();

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.map((item) => item['name'] as String).toList();
      } else {
        throw ServerException(
          'Failed to fetch template items',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch template items: $e');
    }
  }

  @override
  Future<List<String>> getItemAttributes() async {
    try {
      final response = await itemProvider.getItemAttributes();

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.map((item) => item['name'] as String).toList();
      } else {
        throw ServerException(
          'Failed to fetch item attributes',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch item attributes: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getItemAttributeDetails(
    String attributeName,
  ) async {
    try {
      final response = await itemProvider.getItemAttributeDetails(attributeName);

      if (response.statusCode == 200) {
        return response.data['data'] as Map<String, dynamic>;
      } else {
        throw ServerException(
          'Failed to fetch attribute details',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch attribute details: $e');
    }
  }

  @override
  Future<List<String>> getItemVariantsByAttribute(
    String attribute,
    String value,
  ) async {
    try {
      final response = await itemProvider.getItemVariantsByAttribute(
        attribute,
        value,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.map((item) => item['parent'] as String).toList();
      } else {
        throw ServerException(
          'Failed to fetch item variants',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch item variants: $e');
    }
  }

  @override
  Future<List<WarehouseStock>> getStockLevels(String itemCode) async {
    try {
      final response = await itemProvider.getStockLevels(itemCode);

      if (response.statusCode == 200) {
        final result = response.data['message']?['result'] ?? [];
        return (result as List)
            .map((item) => WarehouseStock.fromJson(item))
            .toList();
      } else {
        throw ServerException(
          'Failed to fetch stock levels',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch stock levels: $e');
    }
  }

  @override
  Future<List<WarehouseStock>> getWarehouseStock(String warehouse) async {
    try {
      final response = await itemProvider.getWarehouseStock(warehouse);

      if (response.statusCode == 200) {
        final result = response.data['message']?['result'] ?? [];
        return (result as List)
            .map((item) => WarehouseStock.fromJson(item))
            .toList();
      } else {
        throw ServerException(
          'Failed to fetch warehouse stock',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch warehouse stock: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getStockLedger(
    String itemCode, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      final response = await itemProvider.getStockLedger(
        itemCode,
        fromDate: fromDate,
        toDate: toDate,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.cast<Map<String, dynamic>>();
      } else {
        throw ServerException(
          'Failed to fetch stock ledger',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch stock ledger: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getBatchWiseHistory(
    String itemCode,
  ) async {
    try {
      final response = await itemProvider.getBatchWiseHistory(itemCode);

      if (response.statusCode == 200) {
        final result = response.data['message']?['result'] ?? [];
        return (result as List).cast<Map<String, dynamic>>();
      } else {
        throw ServerException(
          'Failed to fetch batch history',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      if (e is ServerException) rethrow;
      throw ServerException('Failed to fetch batch history: $e');
    }
  }

  /// Handle Dio errors and convert to appropriate exceptions
  AppException _handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkException('Connection timeout. Please check your network.');
      case DioExceptionType.connectionError:
        return NetworkException('No internet connection. Please check your network.');
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        final message = error.response?.data?['message'] ??
            error.response?.data?['error'] ??
            'Server error occurred';
        if (statusCode == 401 || statusCode == 403) {
          return AuthException(message, statusCode);
        }
        return ServerException(message, statusCode);
      case DioExceptionType.cancel:
        return NetworkException('Request cancelled');
      default:
        return ServerException('Unexpected error: ${error.message}');
    }
  }
}
