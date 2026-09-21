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
import 'package:multimax/app/data/utils/awesome_bar_query.dart';

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
    debounce(searchQuery, (_) => fetch(clear: true),
        time: const Duration(milliseconds: 500));
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

  @override
  void onReady() {
    super.onReady();
    // "Find x in <DocType>" from the Awesome Bar seeds the list search.
    final awesomeBarQuery = awesomeBarQueryArg();
    if (awesomeBarQuery != null) onSearchChanged(awesomeBarQuery);
  }

  void onSearchChanged(String v) => searchQuery.value = v;

  void setScope(ActionableScope s) {
    if (scope.value == s) return;
    scope.value = s;
    fetch(clear: true);
  }

  /// Single-select quick chip; tapping the active chip clears it.
  void setStatusChip(String? status) {
    if (status == null || activeFilters['status'] == status) {
      activeFilters.remove('status');
    } else {
      activeFilters['status'] = status;
    }
    fetch(clear: true);
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
    if (searchQuery.value.isEmpty) {
      fetch(clear: true);
    } else {
      searchQuery.value = '';
    }
  }

  Future<void> fetch({bool isLoadMore = false, bool clear = false}) async {
    if (isLoadMore) {
      if (isFetchingMore.value || !hasMore.value) return;
      isFetchingMore.value = true;
    } else {
      isLoading.value = true;
      if (clear) {
        _page = 0;
        hasMore.value = true;
      }
    }
    try {
      final f = Map<String, dynamic>.from(activeFilters);
      final email = _email;
      if (scope.value == ActionableScope.mine &&
          !f.containsKey('owner') && email != null && email.isNotEmpty) {
        f['owner'] = email;
      }
      final q = searchQuery.value.trim();
      final res = await _provider.getSalesOrders(
          limit: _limit,
          limitStart: _page * _limit,
          filters: f,
          orFilters: q.isEmpty
              ? null
              : {'name': ['like', '%$q%'], 'customer_name': ['like', '%$q%']});
      final data = (res.data is Map) ? res.data['data'] : null;
      if (res.statusCode == 200 && data is List) {
        final rows = data
            .map((e) => SalesOrder.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (rows.length < _limit) hasMore.value = false;
        isLoadMore ? orders.addAll(rows) : orders.assignAll(rows);
        _page++;
      } else {
        _error(isLoadMore, clear);
      }
    } catch (e) {
      _error(isLoadMore, clear, e.toString());
    } finally {
      isLoadMore ? isFetchingMore.value = false : isLoading.value = false;
    }
  }

  void _error(bool more, bool clear, [String? msg]) => GlobalDialog.showError(
        title: 'Could not load Sales Orders',
        message: msg ??
            'The server returned an unexpected response. '
                'Check your connection and try again.',
        onRetry: () => fetch(isLoadMore: more, clear: clear),
      );

  void openCreate() => Get.toNamed(AppRoutes.SALES_ORDER_FORM,
      arguments: {'name': '', 'mode': 'new'});

  void open(SalesOrder so) => Get.toNamed(AppRoutes.SALES_ORDER_FORM,
      arguments: {'name': so.name, 'mode': so.docstatus == 0 ? 'edit' : 'view'});
}
