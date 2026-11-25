import 'dart:async';

import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';
import 'package:multimax/app/data/models/user_model.dart';
import 'package:multimax/app/data/providers/sales_order_provider.dart';
import 'package:multimax/app/data/providers/user_provider.dart';
import 'package:multimax/app/data/routes/app_routes.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/global_widgets/global_dialog.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_strip.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';

class SalesOrderController extends GetxController {
  final SalesOrderProvider _provider = Get.find<SalesOrderProvider>();
  final UserProvider _userProvider = Get.find<UserProvider>();

  final isLoading = true.obs;
  final isFetchingMore = false.obs;
  final hasMore = true.obs;
  final orders = <SalesOrder>[].obs;
  final activeFilters = <String, dynamic>{}.obs;
  final searchQuery = ''.obs;
  final scope = ActionableScope.everyone.obs;
  static const _limit = 20;
  int _page = 0;
  int _generation = 0;
  _SalesOrderCriteria? _committedCriteria;
  _SalesOrderCriteria? _requestedCriteria;
  Completer<void>? _fullLoad;
  bool _quickChanging = false;
  Timer? _searchDebounce;

  // Owner picker — lazily loaded from the filter sheet's initState, not here,
  // so the list doesn't pay for the fetch up front.
  final users = <User>[].obs;
  final isFetchingUsers = false.obs;

  /// Quick status chips shown under the header (v15 status options).
  static const statusChips = [
    'Draft', 'To Deliver and Bill', 'To Deliver', 'To Bill',
    'On Hold', 'Completed', 'Closed', 'Cancelled',
  ];

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args is Map && args['filters'] is Map) {
      // The dashboard can be viewed as another user (selectedFilterUser), so an
      // incoming `owner` isn't necessarily the signed-in user: resolveIncoming-
      // ListFilters only folds it into the personal `mine` scope when it IS
      // this user — otherwise it's kept as an explicit Owner filter (chip +
      // query) under `everyone`.
      final r = resolveIncomingListFilters(
          Map<String, dynamic>.from(args['filters'] as Map), _email);
      activeFilters.assignAll(r.filters);
      if (r.mine) scope.value = ActionableScope.mine;
    }
    fetch(clear: true);
  }

  @override
  void onClose() {
    _generation++;
    _searchDebounce?.cancel();
    super.onClose();
  }

  String? get _email {
    try {
      return Get.find<AuthenticationController>().currentUser.value?.email;
    } catch (_) {
      return null;
    }
  }

  Future<void> fetchUsers() async {
    if (users.isNotEmpty) return;
    isFetchingUsers.value = true;
    try {
      final response = await _userProvider.getUsers();
      if (response.statusCode == 200 && response.data['data'] != null) {
        final List<dynamic> data = response.data['data'];
        users.value = data.map((json) => User.fromJson(json)).toList();
      }
    } catch (e) {
      // non-fatal — picker shows empty list
    } finally {
      isFetchingUsers.value = false;
    }
  }

  void onSearchChanged(String value) {
    if (isClosed) return;
    if (value.trim() != searchQuery.value.trim()) {
      // The visible query changes now, so ownership must change before the
      // debounced replacement request starts.
      _generation++;
      _fullLoad = null;
      isLoading.value = true;
      isFetchingMore.value = false;
      _discardRows();
      _searchDebounce?.cancel();
      _searchDebounce = Timer(
        const Duration(milliseconds: 500),
        () => fetch(clear: true),
      );
    }
    searchQuery.value = value;
  }

  void clearSearch() {
    onSearchChanged('');
    fetch(clear: true);
  }

  void setScope(ActionableScope s) {
    if (scope.value == s) return;
    _applyQuick(() => scope.value = s);
  }

  /// Single-select quick chip; tapping the active chip clears it.
  void setStatusChip(String? status) {
    _applyQuick(() {
      if (status == null || activeFilters['status'] == status) {
        activeFilters.remove('status');
      } else {
        activeFilters['status'] = status;
      }
    });
  }

  void _applyQuick(void Function() change) {
    if (isClosed || isLoading.value || _quickChanging) return;
    _quickChanging = true;
    try {
      change();
      fetch(clear: true);
    } finally {
      _quickChanging = false;
    }
  }

  void applyFilters(Map<String, dynamic> f) {
    activeFilters.assignAll(f);
    fetch(clear: true);
  }

  void removeFilter(String key) {
    activeFilters.remove(key);
    fetch(clear: true);
  }

  void clearFilters() {
    activeFilters.clear();
    clearSearch();
  }

  _SalesOrderCriteria get _criteria {
    final filters = Map<String, dynamic>.from(activeFilters);
    final email = _email;
    if (scope.value == ActionableScope.mine &&
        !filters.containsKey('owner') &&
        email != null &&
        email.isNotEmpty) {
      filters['owner'] = email;
    }
    return _SalesOrderCriteria(
      searchQuery.value.trim(),
      _freezeFilters(filters),
    );
  }

  Future<void> fetch({bool isLoadMore = false, bool clear = false}) {
    if (isClosed) return Future.value();
    final criteria = _criteria;
    if (isLoadMore) {
      if (isLoading.value ||
          isFetchingMore.value ||
          !hasMore.value ||
          criteria != _committedCriteria) {
        return Future.value();
      }
      isFetchingMore.value = true;
      return _fetchPage(criteria, _generation, _page, append: true);
    }

    _searchDebounce?.cancel();
    final pending = _fullLoad;
    if (pending != null && criteria == _requestedCriteria) {
      return pending.future;
    }
    final load = Completer<void>();
    final generation = ++_generation;
    _fullLoad = load;
    _requestedCriteria = criteria;
    isLoading.value = true;
    isFetchingMore.value = false;
    if (criteria != _committedCriteria) _discardRows();
    load.complete(_fetchPage(criteria, generation, 0, append: false));
    return load.future;
  }

  void _discardRows() {
    _page = 0;
    _committedCriteria = null;
    hasMore.value = true;
    orders.clear();
  }

  bool _ownsPage(int generation, int page, bool append) =>
      !isClosed && generation == _generation && (!append || page == _page);

  Future<void> _fetchPage(
    _SalesOrderCriteria criteria,
    int generation,
    int page, {
    required bool append,
  }) async {
    try {
      final q = criteria.query;
      final res = await _provider.getSalesOrders(
        limit: _limit,
        limitStart: page * _limit,
        filters: criteria.filters,
        orFilters: q.isEmpty
            ? null
            : {
                'name': ['like', '%$q%'],
                'customer_name': ['like', '%$q%'],
              },
      );
      if (!_ownsPage(generation, page, append)) return;
      final data = (res.data is Map) ? res.data['data'] : null;
      if (res.statusCode == 200 && data is List) {
        final rows = data
            .map((e) => SalesOrder.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _page = page + 1;
        _committedCriteria = criteria;
        hasMore.value = rows.length >= _limit;
        append ? orders.addAll(rows) : orders.assignAll(rows);
      } else {
        _error(criteria, generation, page, append);
      }
    } catch (e) {
      if (_ownsPage(generation, page, append)) {
        _error(criteria, generation, page, append, e.toString());
      }
    } finally {
      if (!isClosed && generation == _generation) {
        if (append) {
          isFetchingMore.value = false;
        } else {
          _fullLoad = null;
          isLoading.value = false;
        }
      }
    }
  }

  void _error(
    _SalesOrderCriteria criteria,
    int generation,
    int page,
    bool append, [
    String? msg,
  ]) {
    if (criteria != _criteria) return;
    GlobalDialog.showError(
      title: 'Could not load Sales Orders',
      message:
          msg ??
          'The server returned an unexpected response. '
              'Check your connection and try again.',
      onRetry: () {
        if (_ownsPage(generation, page, append) && criteria == _criteria) {
          fetch(isLoadMore: append, clear: !append);
        }
      },
    );
  }

  void openCreate() => Get.toNamed(AppRoutes.SALES_ORDER_FORM,
      arguments: {'name': '', 'mode': 'new'});

  void open(SalesOrder so) => Get.toNamed(AppRoutes.SALES_ORDER_FORM,
      arguments: {'name': so.name, 'mode': so.docstatus == 0 ? 'edit' : 'view'});
}

Map<String, dynamic> _freezeFilters(Map<String, dynamic> filters) =>
    Map.unmodifiable(
      filters.map((key, value) => MapEntry(key, _freeze(value))),
    );

Object? _freeze(Object? value) => switch (value) {
  List<Object?>() => List<Object?>.unmodifiable(value.map(_freeze)),
  Map<Object?, Object?>() => Map<Object?, Object?>.unmodifiable(
    value.map((k, v) => MapEntry(k, _freeze(v))),
  ),
  _ => value,
};

class _SalesOrderCriteria {
  const _SalesOrderCriteria(this.query, this.filters);

  static const _equality = DeepCollectionEquality();

  final String query;
  final Map<String, dynamic> filters;

  @override
  bool operator ==(Object other) =>
      other is _SalesOrderCriteria &&
      query == other.query &&
      _equality.equals(filters, other.filters);

  @override
  int get hashCode => Object.hash(query, _equality.hash(filters));
}
