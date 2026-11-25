import 'dart:async';

import 'package:collection/collection.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/suppliers_by_item_report.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/auth/authentication_controller.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_fields.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_layout.dart';
import 'package:multimax/app/modules/stock/reports/suppliers_by_item/suppliers_by_item_rows.dart';

typedef _FieldsOwner = ({String? rawUser, String? mirror});

class _HierarchyExpansion {
  Set<SuppliersByItemRowKey> known = const {};
  final browse = <SuppliersByItemRowKey>{};
  final search = <SuppliersByItemRowKey>{};
}

class SuppliersByItemController extends GetxController {
  SuppliersByItemController({
    required ApiProvider api,
    SuppliersByItemFilters initialFilters = const SuppliersByItemFilters(),
    StorageService? storage,
    FutureOr<String?> Function()? siteResolver,
  }) : _api = api,
       _storage =
           storage ??
           (Get.isRegistered<StorageService>()
               ? Get.find<StorageService>()
               : null),
       _siteResolver = siteResolver,
       filters = initialFilters.obs;

  final ApiProvider _api;
  final StorageService? _storage;
  final FutureOr<String?> Function()? _siteResolver;
  Worker? _fieldUserWorker;
  void Function()? _stopWatchingFields;
  void Function()? _stopWatchingView;
  void Function()? _stopWatchingFieldsOwner;
  _FieldsOwner? _lastFieldsOwner;
  SuppliersByItemFieldsScope? _fieldsScope;
  SuppliersByItemFieldsSnapshot? _fieldsSnapshot;
  SuppliersByItemViewSnapshot? _viewSnapshot;
  Future<void>? _pendingFieldsLoad;
  int _fieldsGeneration = 0;
  int _fieldsActionRevision = 0;
  bool _disposing = false;
  final _fieldVisibility = const SuppliersByItemFieldVisibility.defaults().obs;
  final fieldsScopeLoading = false.obs;
  final settingsScopeLoadError = RxnString();
  final fieldsSaving = false.obs;
  final fieldsResetting = false.obs;
  final fieldsRetrying = false.obs;
  final fieldsSessionOnly = false.obs;
  final fieldsLoadError = RxnString();
  final fieldsSaveError = RxnString();
  final _pendingFieldEdits = <SuppliersByItemField>{}.obs;
  final view = const SuppliersByItemView().obs;
  final viewSaving = false.obs;
  final viewRetrying = false.obs;
  final viewLoadError = RxnString();
  final viewSaveError = RxnString();
  static const _loadError = "Couldn't load settings";
  static const _saveError =
      "Couldn't save Fields. Your choices apply to this session.";
  static const _saveViewError =
      "Couldn't save View. Your choices apply to this session.";

  final Rx<SuppliersByItemFilters> filters;
  final activeFilters = <String, String>{}.obs;
  final nodes = <SuppliersByItemNode>[].obs;
  final isLoading = false.obs;
  final error = RxnString();

  final query = ''.obs;
  final loadedRevision = 0.obs;
  final filterRevision = 0.obs;
  final _resultsLoaded = false.obs;
  final _displayRevision = 0.obs;
  SuppliersByItemIndex _index = indexReport(const []);
  late SuppliersByItemSummary _summary = summarize(_index);
  bool _showPlaceholders = false;
  List<SuppliersByItemLayoutRow> _projection = const [];
  final _modeExpansion = <SuppliersByItemGroup, _HierarchyExpansion>{};
  SuppliersByItemSearch? _search;
  late SuppliersByItemVisibleRows _visibleRows = flattenTemplateView(
    _projection,
    const {},
  );
  final _browseDetails = <SuppliersByItemSourceKey>{};
  final _searchDetails = <SuppliersByItemSourceKey>{};

  bool get hasLoaded => _resultsLoaded.value;

  SuppliersByItemSummary get summary {
    _displayRevision.value;
    return _summary;
  }

  SuppliersByItemVisibleRows get visibleRows {
    _displayRevision.value;
    return _visibleRows;
  }

  SuppliersByItemSearch? get search {
    _displayRevision.value;
    return _search;
  }

  _HierarchyExpansion get _mode =>
      _modeExpansion.putIfAbsent(view.value.group, _HierarchyExpansion.new);

  Set<SuppliersByItemRowKey> get _openBranches =>
      _search == null ? _mode.browse : _mode.search;

  Set<SuppliersByItemSourceKey> get _openDetails =>
      _search == null ? _browseDetails : _searchDetails;

  Set<SuppliersByItemRowKey> get _forcedOpen => _search?.forcedOpen ?? const {};

  Set<SuppliersByItemRowKey> get _visibleBranches => _search == null
      ? _mode.known
      : structuralKeys(_projection, search: _search);

  bool isExpanded(String nodeId) => isBranchExpanded((nodeId: nodeId));

  bool isBranchExpanded(SuppliersByItemRowKey key) {
    _displayRevision.value;
    return _openBranches.contains(key) || _forcedOpen.contains(key);
  }

  bool isSupplierExpanded(String nodeId) => isPairExpanded((nodeId: nodeId));

  bool isPairExpanded(SuppliersByItemSourceKey key) {
    _displayRevision.value;
    return _openDetails.contains(key);
  }

  bool canToggleBranch(String nodeId) => canToggleBranchKey((nodeId: nodeId));

  bool canToggleBranchKey(SuppliersByItemRowKey key) =>
      hasLoaded &&
      !isLoading.value &&
      _visibleRows.indexByKey.containsKey(key) &&
      _mode.known.contains(key) &&
      !_forcedOpen.contains(key);

  void toggleBranch(String nodeId) => toggleBranchKey((nodeId: nodeId));

  void toggleBranchKey(SuppliersByItemRowKey key) {
    if (!canToggleBranchKey(key)) return;
    if (!_openBranches.remove(key)) _openBranches.add(key);
    _updateDisplay();
  }

  void toggleSupplier(String nodeId) => togglePair((nodeId: nodeId));

  void togglePair(SuppliersByItemSourceKey key) {
    if (!hasLoaded ||
        isLoading.value ||
        !_visibleRows.rows.any((row) => row.pairKey == key)) {
      return;
    }
    if (!_openDetails.remove(key)) _openDetails.add(key);
    _displayRevision.value++;
  }

  bool get canExpandAll {
    _displayRevision.value;
    return hasLoaded &&
        !isLoading.value &&
        _visibleBranches.any(
          (key) => !_openBranches.contains(key) && !_forcedOpen.contains(key),
        );
  }

  bool get canCollapseAll {
    _displayRevision.value;
    return hasLoaded &&
        !isLoading.value &&
        _visibleRows.rows.any(
          (row) =>
              (_openBranches.contains(row.key) &&
                  !_forcedOpen.contains(row.key)) ||
              _hasOpenPair(row),
        );
  }

  bool _hasOpenPair(SuppliersByItemLayoutRow row) {
    final pair = row.pairNode;
    return pair != null &&
        _openDetails.contains(row.pairKey) &&
        suppliersByItemHasDetails(pair.row, fieldVisibility.shows);
  }

  void expandAll() {
    if (!canExpandAll) return;
    _openBranches.addAll(_visibleBranches.difference(_forcedOpen));
    _updateDisplay();
  }

  void collapseAll() {
    if (!canCollapseAll) return;
    final branches = _openBranches;
    final details = _openDetails;
    for (final row in _retainedProjection.rows) {
      branches.remove(row.key);
      details.remove(row.pairKey);
    }
    _updateDisplay();
  }

  void setQuery(String value) {
    if (value == query.value) return;
    if (value.trim().isEmpty) {
      _search = null;
      for (final mode in _modeExpansion.values) {
        mode.search.clear();
      }
      _searchDetails.clear();
    } else {
      if (query.value.trim().isEmpty) {
        for (final mode in _modeExpansion.values) {
          mode.search.addAll(mode.browse);
        }
        _searchDetails.addAll(_browseDetails);
      }
      if (hasLoaded) _updateSearch(view.value.group, value);
    }
    query.value = value;
    _updateDisplay();
  }

  void _updateDisplay() {
    _visibleRows = flattenTemplateView(_projection, {
      ..._openBranches,
      ..._forcedOpen,
    }, search: _search);
    _displayRevision.value++;
  }

  void _updateSearch(SuppliersByItemGroup group, String value) {
    _search = value.trim().isEmpty
        ? null
        : searchIndex(
            _index,
            value,
            group: group,
            showPlaceholders: _showPlaceholders,
          );
  }

  SuppliersByItemVisibleRows get _retainedProjection =>
      flattenTemplateView(_projection, _visibleBranches, search: _search);

  String? _directPairSupplier(SuppliersByItemNode? pair) {
    final sourceOwner = _index.nodesById[pair?.row.parentId]?.row;
    if (sourceOwner?.kind != SuppliersByItemRowKind.item ||
        sourceOwner?.isComponent != false) {
      return null;
    }
    return pair?.row.supplier;
  }

  SuppliersByItemRowKey? revealAnchorOccurrence({
    required SuppliersByItemRowKey key,
    SuppliersByItemSourceKey? sourceKey,
    SuppliersByItemSourceKey? ownerKey,
    SuppliersByItemSourceKey? pairKey,
  }) {
    final visible = _visibleRows;
    if (visible.indexByKey.containsKey(key)) return key;
    final retained = _retainedProjection;
    SuppliersByItemLayoutRow? preferVisible(
      bool Function(SuppliersByItemLayoutRow) matches,
    ) =>
        visible.rows.firstWhereOrNull(matches) ??
        retained.rows.firstWhereOrNull(matches);

    final exact = retained.indexByKey[key];
    SuppliersByItemLayoutRow? target;
    if (exact != null) {
      target = retained.rows[exact];
    } else {
      if (pairKey != null) {
        target = preferVisible(
          (row) => row.ownerKey == ownerKey && row.pairKey == pairKey,
        );
        // Supplier mode emits one item entry for duplicate source pairs.
        final supplier = _directPairSupplier(_index.nodesById[pairKey.nodeId]);
        if (target == null && ownerKey != null && supplier != null) {
          target = preferVisible(
            (row) =>
                row.ownerKey == ownerKey &&
                _directPairSupplier(row.pairNode) == supplier,
          );
        }
      } else if ((sourceKey ?? (key is SuppliersByItemSourceKey ? key : null))
          case final source?) {
        target = preferVisible(
          (row) =>
              row.group == null &&
              row.pairKey == null &&
              row.ownerKey == ownerKey &&
              row.sourceKey == source,
        );
      }
      if (target == null && ownerKey != null) {
        target = preferVisible((row) => row.ownerKey == ownerKey);
      }
    }
    if (target == null) return null;
    final ancestors = target.ancestorKeys
        .where(
          (ancestor) =>
              !_forcedOpen.contains(ancestor) &&
              !_openBranches.contains(ancestor),
        )
        .toList();
    if (ancestors.isNotEmpty) {
      _openBranches.addAll(ancestors);
      _updateDisplay();
    }
    return target.key;
  }

  List<SuppliersByItemLayoutRow> _project(SuppliersByItemView selection) =>
      selection.group == SuppliersByItemGroup.supplier
      ? buildSupplierView(
          _index,
          showPlaceholders: _showPlaceholders,
          view: selection,
        )
      : buildTemplateView(
          _index,
          showPlaceholders: _showPlaceholders,
          view: selection,
        );

  void _syncExpansion(
    SuppliersByItemGroup group,
    List<SuppliersByItemLayoutRow> projection,
  ) {
    final firstVisit = !_modeExpansion.containsKey(group);
    final mode = _modeExpansion.putIfAbsent(group, _HierarchyExpansion.new);
    final previousBranches = mode.known;
    mode.known = structuralKeys(projection);
    final defaults =
        group == SuppliersByItemGroup.template ||
            firstVisit ||
            previousBranches.isEmpty
        ? defaultExpansion(_index, projection, group: group)
        : const <SuppliersByItemRowKey>{};
    final newlyOpen = defaults.difference(previousBranches);
    mode.browse
      ..retainAll(mode.known)
      ..addAll(newlyOpen);
    if (query.value.trim().isNotEmpty) {
      mode.search
        ..retainAll(mode.known)
        ..addAll(newlyOpen);
    }
  }

  void _applyView(SuppliersByItemView selection) {
    if (view.value == selection) return;
    if (hasLoaded) {
      _projection = _project(selection);
      _syncExpansion(selection.group, _projection);
      _updateSearch(selection.group, query.value);
    }
    view.value = selection;
    if (hasLoaded) _updateDisplay();
  }

  void _applyResult(List<SuppliersByItemNode> result, bool showPlaceholders) {
    _index = indexReport(result);
    _showPlaceholders = showPlaceholders;
    _summary = summarize(_index);
    final selection = view.value;
    _projection = _project(selection);
    for (final group in _modeExpansion.keys.toList()) {
      if (group != selection.group) {
        _syncExpansion(group, _project(selection.copyWith(group: group)));
      }
    }
    _syncExpansion(selection.group, _projection);
    _browseDetails.removeWhere(
      (key) => !_index.nodesById.containsKey(key.nodeId),
    );
    _searchDetails.removeWhere(
      (key) => !_index.nodesById.containsKey(key.nodeId),
    );
    _updateSearch(selection.group, query.value);
    nodes.assignAll(result);
    loadedRevision.value++;
    _updateDisplay();
    _resultsLoaded.value = true;
  }

  void _clearResult() {
    _resultsLoaded.value = false;
    _index = indexReport(const []);
    _projection = const [];
    _summary = summarize(_index);
    _search = null;
    nodes.clear();
    _updateDisplay();
  }

  SuppliersByItemFieldVisibility get fieldVisibility => _fieldVisibility.value;

  bool get fieldsEditable =>
      !fieldsScopeLoading.value &&
      settingsScopeLoadError.value == null &&
      fieldsLoadError.value == null &&
      (fieldsSessionOnly.value || _fieldsSnapshot?.loaded == true);

  bool get viewEditable =>
      !fieldsScopeLoading.value &&
      settingsScopeLoadError.value == null &&
      viewLoadError.value == null &&
      (fieldsSessionOnly.value || _viewSnapshot?.loaded == true);

  bool isSavingField(SuppliersByItemField field) =>
      _pendingFieldEdits.contains(field);

  String? get _fieldUser {
    if (Get.isRegistered<AuthenticationController>()) {
      final id = Get.find<AuthenticationController>().currentUser.value?.id;
      if (id != null && id.trim().isNotEmpty) return id;
    }
    final id = _storage?.getUser()?.id;
    return id != null && id.trim().isNotEmpty ? id : null;
  }

  _FieldsOwner get _fieldsOwner =>
      (rawUser: _fieldUser, mirror: _storage?.getBaseUrl());

  @override
  void onInit() {
    super.onInit();
    _stopWatchingFieldsOwner = _storage?.watchSuppliersByItemFieldsOwner(() {
      if (_lastFieldsOwner != _fieldsOwner) unawaited(refreshFieldsScope());
    });
    if (Get.isRegistered<AuthenticationController>()) {
      _fieldUserWorker = ever(
        Get.find<AuthenticationController>().currentUser,
        (_) {
          if (_lastFieldsOwner != _fieldsOwner) unawaited(refreshFieldsScope());
        },
      );
    }
    unawaited(refreshFieldsScope());
    unawaited(run());
  }

  Future<void> refreshFieldsScope() {
    if (_disposing) return Future.value();
    final owner = _fieldsOwner;
    final pending = _pendingFieldsLoad;
    if (_lastFieldsOwner == owner && pending != null) return pending;

    final generation = ++_fieldsGeneration;
    if (_lastFieldsOwner != owner) {
      _lastFieldsOwner = owner;
      fieldsScopeLoading.value = true;
      _switchFieldsScope(null);
      fieldsSessionOnly.value = false;
    } else if (settingsScopeLoadError.value != null) {
      fieldsScopeLoading.value = true;
    }

    final operation = _resolveFieldsScope(owner, generation).whenComplete(() {
      if (_fieldsGeneration == generation) {
        _pendingFieldsLoad = null;
        fieldsScopeLoading.value = false;
      }
    });
    _pendingFieldsLoad = operation;
    return operation;
  }

  Future<void> _resolveFieldsScope(_FieldsOwner owner, int generation) async {
    final storage = _storage;
    final rawUser = owner.rawUser;
    if (rawUser == null ||
        storage == null ||
        !storage.hasSuppliersByItemFieldsStore) {
      fieldsSessionOnly.value = true;
      fieldsScopeLoading.value = false;
      return;
    }

    String? site;
    try {
      final resolver = _siteResolver;
      final configured = resolver != null
          ? await resolver()
          : owner.mirror?.trim().isNotEmpty == true
          ? owner.mirror
          : await storage.getSuppliersByItemSite();
      site = normalizeSuppliersByItemSite(configured);
    } catch (_) {
      if (_fieldsGeneration == generation) {
        settingsScopeLoadError.value = _loadError;
        fieldsSessionOnly.value = false;
      }
      return;
    }

    if (_fieldsGeneration != generation) return;
    settingsScopeLoadError.value = null;
    if (site == null) {
      if (_fieldsScope != null) _switchFieldsScope(null);
      fieldsLoadError.value = null;
      viewLoadError.value = null;
      fieldsSessionOnly.value = true;
      return;
    }
    fieldsSessionOnly.value = false;
    final scope = (site: site, user: rawUser.trim());
    if (_fieldsScope != scope) {
      _switchFieldsScope(scope);
      final revision = _fieldsActionRevision;
      bool stillBound() => !_disposing && _fieldsActionRevision == revision;
      _stopWatchingFields = storage.watchSuppliersByItemFields(scope, (
        snapshot,
      ) {
        if (stillBound()) _applyFieldsSnapshot(snapshot);
      });
      _stopWatchingView = storage.watchSuppliersByItemView(scope, (snapshot) {
        if (stillBound()) _applyViewSnapshot(snapshot);
      });
    }
    final snapshot = storage.getSuppliersByItemFields(scope);
    final viewSnapshot = storage.getSuppliersByItemView(scope);
    _applyFieldsSnapshot(snapshot);
    _applyViewSnapshot(viewSnapshot);
    if (!snapshot.loaded || !viewSnapshot.loaded) {
      fieldsScopeLoading.value = true;
      await Future.wait([
        if (!snapshot.loaded)
          storage.loadSuppliersByItemFields(scope, rawUser: rawUser),
        if (!viewSnapshot.loaded) storage.loadSuppliersByItemView(scope),
      ]);
    }
  }

  void _switchFieldsScope(SuppliersByItemFieldsScope? scope) {
    _fieldsActionRevision++;
    _pendingFieldEdits.clear();
    fieldsResetting.value = false;
    fieldsRetrying.value = false;
    _stopWatchingFields?.call();
    _stopWatchingFields = null;
    _stopWatchingView?.call();
    _stopWatchingView = null;
    _fieldsScope = scope;
    _fieldsSnapshot = null;
    _viewSnapshot = null;
    settingsScopeLoadError.value = null;
    fieldsSaving.value = false;
    fieldsLoadError.value = null;
    fieldsSaveError.value = null;
    _fieldVisibility.value = const SuppliersByItemFieldVisibility.defaults();
    viewSaving.value = false;
    viewRetrying.value = false;
    viewLoadError.value = null;
    viewSaveError.value = null;
    _applyView(const SuppliersByItemView());
  }

  void _applyFieldsSnapshot(SuppliersByItemFieldsSnapshot snapshot) {
    final previous = _fieldsSnapshot;
    if (previous != null && snapshot.revision < previous.revision) return;
    _fieldsSnapshot = snapshot;
    if (!identical(previous?.overrides, snapshot.overrides)) {
      _fieldVisibility.value = SuppliersByItemFieldVisibility(
        snapshot.overrides,
      );
    }
    fieldsSaving.value = snapshot.saving;
    fieldsLoadError.value =
        snapshot.failure == SuppliersByItemFieldsFailure.load
        ? _loadError
        : null;
    fieldsSaveError.value =
        snapshot.failure == SuppliersByItemFieldsFailure.save
        ? _saveError
        : null;
  }

  void _applyViewSnapshot(SuppliersByItemViewSnapshot snapshot) {
    final previous = _viewSnapshot;
    if (previous != null && snapshot.revision < previous.revision) return;
    _viewSnapshot = snapshot;
    _applyView(snapshot.view);
    viewSaving.value = snapshot.saving;
    viewLoadError.value = snapshot.failure == SuppliersByItemFieldsFailure.load
        ? _loadError
        : null;
    viewSaveError.value = snapshot.failure == SuppliersByItemFieldsFailure.save
        ? _saveViewError
        : null;
  }

  @override
  void onClose() {
    _disposing = true;
    _fieldsGeneration++;
    _fieldUserWorker?.dispose();
    _stopWatchingFields?.call();
    _stopWatchingView?.call();
    _stopWatchingFieldsOwner?.call();
    super.onClose();
  }

  Future<void> setFieldVisible(SuppliersByItemField field, bool visible) async {
    if (!_pendingFieldEdits.add(field)) return;
    final revision = _fieldsActionRevision;
    try {
      await _editFields(
        (selection) => selection.shows(field) == visible
            ? null
            : selection.withField(field, visible),
      );
    } finally {
      if (!_disposing && _fieldsActionRevision == revision) {
        _pendingFieldEdits.remove(field);
      }
    }
  }

  Future<void> resetFields() async {
    if (fieldsResetting.value) return;
    final revision = _fieldsActionRevision;
    fieldsResetting.value = true;
    try {
      await _editFields((_) => const SuppliersByItemFieldVisibility.defaults());
    } finally {
      if (!_disposing && _fieldsActionRevision == revision) {
        fieldsResetting.value = false;
      }
    }
  }

  Future<void> _editFields(
    SuppliersByItemFieldVisibility? Function(SuppliersByItemFieldVisibility)
    edit,
  ) async {
    if (_disposing) return;
    final owner = _fieldsOwner;
    if (owner != _lastFieldsOwner ||
        fieldsScopeLoading.value ||
        _siteResolver != null ||
        (owner.rawUser != null && owner.mirror?.trim().isNotEmpty != true)) {
      await refreshFieldsScope();
    }
    if (_disposing || owner != _fieldsOwner || !fieldsEditable) return;
    if ((_storage, _fieldsScope) case (final storage?, final scope?)) {
      try {
        await storage.updateSuppliersByItemFields(
          scope,
          (current) => edit(SuppliersByItemFieldVisibility(current))?.overrides,
        );
      } catch (_) {
        // The shared scope keeps the optimistic selection and publishes failure.
      }
    } else {
      final updated = edit(fieldVisibility);
      if (updated != null) _fieldVisibility.value = updated;
    }
  }

  Future<void> retryFields() async {
    if (fieldsScopeLoading.value ||
        fieldsSaving.value ||
        fieldsRetrying.value) {
      return;
    }
    final revision = _fieldsActionRevision;
    fieldsRetrying.value = true;
    try {
      if (settingsScopeLoadError.value == null &&
          _fieldsSnapshot?.loaded == true &&
          fieldsSaveError.value != null) {
        await _editFields((selection) => selection);
      } else {
        await refreshFieldsScope();
      }
    } finally {
      if (!_disposing && _fieldsActionRevision == revision) {
        fieldsRetrying.value = false;
      }
    }
  }

  Future<void> setGroup(SuppliersByItemGroup group) =>
      _editView((current) => current.copyWith(group: group));

  Future<void> setSortField(SuppliersByItemSortField field) => _editView(
    (current) => current.sortField == field
        ? current
        : current.copyWith(
            sortField: field,
            sortDirection: SuppliersByItemSortDirection.desc,
          ),
  );

  Future<void> setSortDirection(SuppliersByItemSortDirection direction) =>
      _editView((current) => current.copyWith(sortDirection: direction));

  Future<void> _editView(
    SuppliersByItemView Function(SuppliersByItemView) edit, {
    bool resave = false,
  }) async {
    if (_disposing) return;
    final owner = _fieldsOwner;
    if (owner != _lastFieldsOwner ||
        fieldsScopeLoading.value ||
        _siteResolver != null ||
        (owner.rawUser != null && owner.mirror?.trim().isNotEmpty != true)) {
      await refreshFieldsScope();
    }
    if (_disposing || owner != _fieldsOwner || !viewEditable) return;
    if ((_storage, _fieldsScope) case (final storage?, final scope?)) {
      try {
        await storage.updateSuppliersByItemView(scope, (current) {
          final next = edit(current);
          return resave || next != current ? next : null;
        });
      } catch (_) {
        // The shared scope keeps the current choice and publishes the error.
      }
    } else {
      _applyView(edit(view.value));
    }
  }

  Future<void> retryView() async {
    if (fieldsScopeLoading.value || viewSaving.value || viewRetrying.value) {
      return;
    }
    final revision = _fieldsActionRevision;
    viewRetrying.value = true;
    try {
      if (settingsScopeLoadError.value == null &&
          _viewSnapshot?.loaded == true &&
          viewSaveError.value != null) {
        await _editView((current) => current, resave: true);
      } else {
        await refreshFieldsScope();
      }
    } finally {
      if (!_disposing && _fieldsActionRevision == revision) {
        viewRetrying.value = false;
      }
    }
  }

  Future<void> run({SuppliersByItemFilters? filters}) async {
    if (_disposing || isClosed || isLoading.value) return;

    isLoading.value = true;
    try {
      _clearResult();
      final selected = filters ?? this.filters.value;
      if (!const DeepCollectionEquality.unordered().equals(
        selected.toJson(),
        this.filters.value.toJson(),
      )) {
        _modeExpansion.clear();
        _browseDetails.clear();
        setQuery('');
        filterRevision.value++;
      }
      this.filters.value = selected;
      activeFilters.assignAll({
        for (final entry in selected.linkFilters.entries)
          entry.key: entry.value.length == 1
              ? entry.value.single
              : '${entry.value.length} selected',
        if (!selected.includeDrafts) 'include_drafts': 'Off',
        if (selected.expandBom) 'expand_bom': 'On',
      });
      error.value = null;
      final result = await _api.runSuppliersByItem(selected);
      if (!_disposing) _applyResult(result, selected.expandBom);
    } on SuppliersByItemReportException catch (e) {
      if (!_disposing) error.value = e.message;
    } catch (_) {
      if (!_disposing) error.value = 'Could not load Suppliers by Item.';
    } finally {
      if (!_disposing) isLoading.value = false;
    }
  }
}
