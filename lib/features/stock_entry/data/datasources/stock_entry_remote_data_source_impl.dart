import 'package:dio/dio.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../app/data/providers/api_provider.dart';
import '../../../../app/data/models/stock_entry_model.dart';
import 'stock_entry_remote_data_source.dart';

/// Implementation of StockEntryRemoteDataSource using existing ApiProvider
class StockEntryRemoteDataSourceImpl implements StockEntryRemoteDataSource {
  final ApiProvider apiProvider;

  StockEntryRemoteDataSourceImpl(this.apiProvider);

  @override
  Future<List<StockEntry>> getStockEntries({
    required int page,
    required int pageSize,
    String? searchQuery,
    Map<String, dynamic>? filters,
  }) async {
    try {
      // Build query parameters
      final queryParams = <String, dynamic>{
        'page': page,
        'page_size': pageSize,
      };

      if (searchQuery != null && searchQuery.isNotEmpty) {
        queryParams['search'] = searchQuery;
      }

      if (filters != null) {
        queryParams.addAll(filters);
      }

      final response = await apiProvider.dio.get(
        '/api/resource/Stock Entry',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        return data.map((json) => StockEntry.fromJson(json)).toList();
      } else {
        throw ServerException(
          'Failed to load stock entries',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
    }
  }

  @override
  Future<StockEntry> getStockEntryById(String id) async {
    try {
      final response = await apiProvider.dio.get(
        '/api/resource/Stock Entry/$id',
      );

      if (response.statusCode == 200) {
        return StockEntry.fromJson(response.data['data']);
      } else {
        throw ServerException(
          'Failed to load stock entry',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
    }
  }

  @override
  Future<StockEntry> createStockEntry(StockEntry stockEntry) async {
    try {
      final response = await apiProvider.dio.post(
        '/api/resource/Stock Entry',
        data: stockEntry.toJson(),
      );

      if (response.statusCode == 200) {
        return StockEntry.fromJson(response.data['data']);
      } else {
        throw ServerException(
          'Failed to create stock entry',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
    }
  }

  @override
  Future<StockEntry> updateStockEntry(StockEntry stockEntry) async {
    try {
      final response = await apiProvider.dio.put(
        '/api/resource/Stock Entry/${stockEntry.name}',
        data: stockEntry.toJson(),
      );

      if (response.statusCode == 200) {
        return StockEntry.fromJson(response.data['data']);
      } else {
        throw ServerException(
          'Failed to update stock entry',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
    }
  }

  @override
  Future<StockEntry> submitStockEntry(String id) async {
    try {
      final response = await apiProvider.dio.post(
        '/api/method/frappe.client.submit',
        data: {
          'doc': {'doctype': 'Stock Entry', 'name': id},
        },
      );

      if (response.statusCode == 200) {
        return StockEntry.fromJson(response.data['message']);
      } else {
        throw ServerException(
          'Failed to submit stock entry',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
    }
  }

  @override
  Future<void> deleteStockEntry(String id) async {
    try {
      final response = await apiProvider.dio.delete(
        '/api/resource/Stock Entry/$id',
      );

      if (response.statusCode != 202 && response.statusCode != 200) {
        throw ServerException(
          'Failed to delete stock entry',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
    }
  }

  @override
  Future<bool> validateRack({
    required String warehouse,
    required String rack,
  }) async {
    try {
      final response = await apiProvider.dio.post(
        '/api/method/multimax.api.validate_rack',
        data: {
          'warehouse': warehouse,
          'rack': rack,
        },
      );

      if (response.statusCode == 200) {
        return response.data['message'] == true;
      } else {
        return false;
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> validateBatch({
    required String itemCode,
    required String warehouse,
    required String batchNo,
  }) async {
    try {
      final fromDate = DateTime.now().subtract(const Duration(days: 365));
      final toDate = DateTime.now();

      final results = await getBatchWiseBalance(
        itemCode: itemCode,
        warehouse: warehouse,
        batchNo: batchNo,
        fromDate: fromDate,
        toDate: toDate,
      );

      if (results.isNotEmpty) {
        final batch = results.first;
        if (batch['balance_qty'] != null && batch['balance_qty'] > 0) {
          return {
            'valid': true,
            'batch': batchNo,
            'balance_qty': batch['balance_qty'],
          };
        }
      }

      return {
        'valid': false,
        'error': 'Batch not found or has zero balance',
      };
    } catch (e) {
      return {
        'valid': false,
        'error': e.toString(),
      };
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getBatchWiseBalance({
    required String itemCode,
    required String warehouse,
    String? batchNo,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final response = await apiProvider.dio.get(
        '/api/resource/Batch-Wise Balance History',
        queryParameters: {
          'filters': [
            ['item_code', '=', itemCode],
            ['warehouse', '=', warehouse],
            if (batchNo != null) ['batch_no', '=', batchNo],
          ],
          'fields': ['batch_no', 'balance_qty', 'warehouse'],
        },
      );

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(response.data['data'] ?? []);
      } else {
        throw ServerException(
          'Failed to get batch balance',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
    }
  }

  @override
  Future<SerialAndBatchBundle> saveSerialBatchBundle(
    SerialAndBatchBundle bundle,
  ) async {
    try {
      final Response response;

      if (bundle.name != null && !bundle.name!.startsWith('local_')) {
        // Update existing bundle
        response = await apiProvider.dio.put(
          '/api/resource/Serial and Batch Bundle/${bundle.name}',
          data: bundle.toJson(),
        );
      } else {
        // Create new bundle
        response = await apiProvider.dio.post(
          '/api/resource/Serial and Batch Bundle',
          data: bundle.toJson(),
        );
      }

      if (response.statusCode == 200) {
        return SerialAndBatchBundle.fromJson(response.data['data']);
      } else {
        throw ServerException(
          'Failed to save bundle',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
    }
  }

  @override
  Future<SerialAndBatchBundle> getSerialBatchBundle(String bundleId) async {
    try {
      final response = await apiProvider.dio.get(
        '/api/resource/Serial and Batch Bundle/$bundleId',
      );

      if (response.statusCode == 200) {
        return SerialAndBatchBundle.fromJson(response.data['data']);
      } else {
        throw ServerException(
          'Failed to load bundle',
          response.statusCode,
        );
      }
    } on DioException catch (e) {
      throw _handleDioError(e);
    } catch (e) {
      throw ServerException('Unexpected error: $e');
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
