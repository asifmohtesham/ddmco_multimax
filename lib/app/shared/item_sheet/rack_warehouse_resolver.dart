import 'package:dio/dio.dart';
import 'package:multimax/app/data/models/rack_warehouse_lookup.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

import 'rack_warehouse_rule.dart';

/// Resolves Rack and Warehouse records for the current authenticated session.
class RackWarehouseResolver {
  RackWarehouseResolver(this._api);

  final ApiProvider _api;
  static final _caches = Expando<_RackCache>();
  static const _cacheLifetime = Duration(minutes: 2);

  Future<RackPairVerdict> check({
    required String rack,
    required String? rowWarehouse,
    required String company,
    required RackSide side,
    bool applicable = true,
    bool initializeWarehouse = false,
  }) async {
    final candidate = rack.trim();
    RackPairVerdict verdict(
      String name, {
      String? warehouse,
      RackPairIssue? issue,
    }) => evaluateRackPair(
      rack: name,
      side: side,
      rackWarehouse: warehouse,
      rowWarehouse: rowWarehouse,
      applicable: applicable,
      initializeWarehouse: initializeWarehouse,
      lookupIssue: issue,
    );

    if (candidate.isEmpty || !applicable) return verdict(candidate);

    final session = _api.rackWarehouseSession;
    final existing = _caches[_api];
    final cache = existing?.session == session
        ? existing!
        : _RackCache(session);
    _caches[_api] = cache;
    final key = (company, candidate);
    final cached = cache.resolved[key];
    if (cached != null && DateTime.now().isBefore(cached.expires)) {
      return verdict(cached.name, warehouse: cached.warehouse);
    }

    var canonical = candidate;
    try {
      var lookup = await _api.getRackWarehouse(candidate);
      if (lookup.status == RackLookupStatus.notFound &&
          candidate.contains(' - ')) {
        final alias = rackAlias(candidate, await _abbreviation(company, cache));
        if (alias != null) {
          lookup = await _api.getRackWarehouse(alias);
        }
      }
      if (lookup.status == RackLookupStatus.notFound) {
        return verdict(candidate, issue: RackPairIssue.notFound);
      }
      if (lookup.status == RackLookupStatus.error) {
        return verdict(candidate, issue: RackPairIssue.unavailable);
      }
      canonical = lookup.name ?? candidate;
      final link = warehouseValue(lookup.warehouse);
      late final String? resolved;
      if (link != null) {
        final warehouse = await _linkedWarehouse(link, cache);
        resolved = warehouse?.isActiveLeaf(company) == true
            ? warehouse!.name
            : null;
      } else {
        final abbreviation = await _abbreviation(company, cache);
        resolved = abbreviation == null
            ? null
            : warehouseFromRackPrefix(
                rack: canonical,
                company: company,
                abbreviation: abbreviation,
                warehouses: await activeWarehouses(company),
              );
      }
      if (_api.rackWarehouseSession != session) {
        return verdict(candidate, issue: RackPairIssue.unavailable);
      }
      if (resolved == null) {
        return verdict(canonical, issue: RackPairIssue.invalidWarehouse);
      }
      final expires = DateTime.now().add(_cacheLifetime);
      final mapping = (name: canonical, warehouse: resolved, expires: expires);
      cache.resolved
        ..removeWhere((_, entry) => DateTime.now().isAfter(entry.expires))
        ..[key] = mapping
        ..[(company, canonical)] = mapping;
      return verdict(canonical, warehouse: resolved);
    } catch (_) {
      return verdict(canonical, issue: RackPairIssue.unavailable);
    }
  }

  Future<RackWarehouse?> _linkedWarehouse(String name, _RackCache cache) async {
    final cached = cache.warehouses[name];
    if (cached != null && DateTime.now().isBefore(cached.expires)) {
      return cached.warehouse;
    }
    try {
      final response = await _api.getDocument(
        'Warehouse',
        Uri.encodeComponent(name),
      );
      if (response.statusCode == 404) return null;
      final warehouse = _parseWarehouse(_document(response));
      cache.warehouses[name] = (
        warehouse: warehouse,
        expires: DateTime.now().add(_cacheLifetime),
      );
      return warehouse;
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<String?> _abbreviation(String company, _RackCache cache) async {
    if (company.trim().isEmpty) return null;
    final cached = cache.abbreviations[company];
    if (cached != null && DateTime.now().isBefore(cached.expires)) {
      return cached.abbreviation;
    }
    final response = await _api.getDocument(
      'Company',
      Uri.encodeComponent(company),
    );
    final abbr = warehouseValue(_document(response)['abbr'] as String?);
    if (abbr != null) {
      cache.abbreviations[company] = (
        abbreviation: abbr,
        expires: DateTime.now().add(_cacheLifetime),
      );
    }
    return abbr;
  }

  Future<List<RackWarehouse>> activeWarehouses(String company) async {
    if (company.trim().isEmpty) return const [];
    const pageSize = 100;
    final warehouses = <RackWarehouse>[];
    for (var start = 0; ; start += pageSize) {
      final response = await _api.getDocumentList(
        'Warehouse',
        limit: pageSize,
        limitStart: start,
        fields: ['name', 'warehouse_name', 'company', 'is_group', 'disabled'],
        filters: {'company': company, 'is_group': 0, 'disabled': 0},
        orderBy: 'name asc',
      );
      final data = response.data;
      if (response.statusCode != 200 || data is! Map || data['data'] is! List) {
        throw const FormatException('Invalid Warehouse list');
      }
      final records = data['data'] as List;
      warehouses.addAll(
        records
            .map((entry) => _parseWarehouse(entry as Map))
            .where((warehouse) => warehouse.isActiveLeaf(company)),
      );
      if (records.length < pageSize) return warehouses;
    }
  }

  static Map _document(Response response) {
    final body = response.data;
    if (response.statusCode != 200 || body is! Map || body['data'] is! Map) {
      throw const FormatException('Invalid resource response');
    }
    return body['data'] as Map;
  }

  static RackWarehouse _parseWarehouse(Map data) => RackWarehouse(
    name: _requiredString(data['name']),
    warehouseName: _requiredString(data['warehouse_name']),
    company: _requiredString(data['company']),
    isGroup: _check(data['is_group']),
    disabled: _check(data['disabled']),
  );

  static String _requiredString(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value;
    throw const FormatException('Expected resource string');
  }

  static bool _check(Object? value) => switch (value) {
    0 || '0' || false => false,
    1 || '1' || true => true,
    _ => throw const FormatException('Expected resource check value'),
  };
}

class _RackCache {
  _RackCache(this.session);

  final int session;
  final resolved =
      <(String, String), ({String name, String warehouse, DateTime expires})>{};
  final warehouses = <String, ({RackWarehouse warehouse, DateTime expires})>{};
  final abbreviations = <String, ({String abbreviation, DateTime expires})>{};
}
