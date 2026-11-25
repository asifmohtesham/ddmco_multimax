import 'dart:async';

import 'package:get/get.dart';

import 'report_field.dart';
import 'report_fields_store.dart';

abstract interface class ReportFieldsController {
  Rx<FieldsState> get state;
  int get ownerGeneration;
  FieldsScope? get scope;
  Future<void> bind();
  void replaceDefinition(ReportFieldsDefinition next);
  bool selected(String key);
  bool shows(String key);
  bool canEdit(String key);
  Future<void> setVisible(String key, bool visible);
  Future<void> resetToDefaults();
  Future<void> retry();
  void dispose();
}

class ScopedReportFieldsController implements ReportFieldsController {
  ScopedReportFieldsController({
    required ReportFieldsDefinition definition,
    required ReportOwnerSource? owner,
    required ReportFieldsStore? store,
  }) : _initialDefinition = definition.immutable(),
       _ownerSource = owner,
       _store = store {
    _definition = _initialDefinition;
    state = Rx(_currentState);
  }

  factory ScopedReportFieldsController.forReport(
    ReportFieldsDefinition definition,
  ) => ScopedReportFieldsController(
    definition: definition,
    owner: Get.isRegistered<ReportOwnerSource>()
        ? Get.find<ReportOwnerSource>()
        : null,
    store: Get.isRegistered<ReportFieldsStore>()
        ? Get.find<ReportFieldsStore>()
        : null,
  );

  final ReportFieldsDefinition _initialDefinition;
  final ReportOwnerSource? _ownerSource;
  final ReportFieldsStore? _store;
  late ReportFieldsDefinition _definition;
  FieldsSnapshot _snapshot = emptyFieldsSnapshot;
  FieldsOwner? _owner;
  Unsubscribe? _unwatchOwner;
  Unsubscribe? _unwatchStore;
  Future<void>? _bindingTask;
  final _pendingKeys = <String>{};
  var _generation = 0;
  var _hasBound = false;
  var _binding = true;
  var _sessionOnly = false;
  var _resetting = false;
  var _retrying = false;
  var _disposed = false;

  @override
  late final Rx<FieldsState> state;

  @override
  int get ownerGeneration => _generation;

  @override
  FieldsScope? get scope => _owner?.scope;

  FieldsState get _currentState => (
    definition: _definition,
    snapshot: _snapshot,
    binding: _binding,
    sessionOnly: _sessionOnly,
    resetting: _resetting,
    retrying: _retrying,
    pendingKeys: Set.unmodifiable(_pendingKeys),
  );

  void _publish() => state.value = _currentState;

  @override
  Future<void> bind() {
    if (_disposed) return Future.value();
    _unwatchOwner ??= _ownerSource?.watch(_ownerChanged);
    final existing = _bindingTask;
    if (existing != null) return existing;
    late final Future<void> binding;
    binding = _resolve(_generation).whenComplete(() {
      if (identical(_bindingTask, binding)) _bindingTask = null;
    });
    return _bindingTask = binding;
  }

  bool _active(int generation) => !_disposed && _generation == generation;

  void _clearOwner() {
    ++_generation;
    _unwatchStore?.call();
    _unwatchStore = null;
    _definition = _initialDefinition;
    _snapshot = emptyFieldsSnapshot;
    _owner = null;
    _hasBound = false;
    _binding = true;
    _sessionOnly = false;
    _resetting = false;
    _retrying = false;
    _pendingKeys.clear();
    _publish();
  }

  void _ownerChanged() {
    if (_disposed) return;
    _bindingTask = null;
    _clearOwner();
    unawaited(bind());
  }

  Future<void> _resolve(int generation) async {
    FieldsOwner? resolved;
    try {
      resolved = await _ownerSource?.resolve();
    } catch (_) {
      if (!_active(generation)) return;
      if (_hasBound) _clearOwner();
      _snapshot = (
        overrides: const {},
        revision: _snapshot.revision + 1,
        loaded: false,
        saving: false,
        failure: FieldsFailure.load,
      );
      _binding = false;
      _publish();
      return;
    }
    if (!_active(generation)) return;
    if (_hasBound && _owner?.scope == resolved?.scope) return;
    if (_hasBound) {
      _clearOwner();
      generation = _generation;
    }
    _hasBound = true;
    _owner = resolved;
    final store = _store;
    if (resolved == null || store == null) {
      _snapshot = emptyFieldsSnapshot;
      _sessionOnly = true;
      _binding = false;
      _publish();
      return;
    }
    final id = _definition.id;
    final scope = resolved.scope;
    _snapshot = store.snapshot(id, scope);
    _unwatchStore = store.watch(id, scope, (next) {
      if (!_active(generation)) return;
      _snapshot = next;
      _publish();
    });
    _publish();
    await store.load(id, resolved);
    if (!_active(generation)) return;
    _snapshot = store.snapshot(id, scope);
    _binding = false;
    _publish();
  }

  @override
  void replaceDefinition(ReportFieldsDefinition next) {
    if (_disposed) return;
    assert(next.id == _definition.id, 'The presentation ID cannot change');
    _definition = next.immutable();
    _publish();
  }

  @override
  bool selected(String key) => state.value.selected(key);

  @override
  bool shows(String key) => state.value.shows(key);

  @override
  bool canEdit(String key) => state.value.canEdit(key);

  Future<void> _verifiedEdit(
    int generation,
    Future<void> Function() apply,
  ) async {
    final currentScope = scope;
    final store = _store;
    Future<bool> verify() async {
      if (!_active(generation)) return false;
      await bind();
      return _active(generation) &&
          !_binding &&
          _snapshot.failure != FieldsFailure.load &&
          (_sessionOnly || _snapshot.loaded);
    }

    if (currentScope == null || store == null) {
      if (await verify()) await apply();
    } else {
      await store.sequenceEdit(_definition.id, currentScope, verify, apply);
    }
  }

  @override
  Future<void> setVisible(String key, bool visible) async {
    if (_disposed || !canEdit(key)) return;
    final generation = _generation;
    _pendingKeys.add(key);
    try {
      final edit = _verifiedEdit(generation, () async {
        final field = _definition.field(key);
        final dependency = field?.requiresKey;
        if (field == null ||
            field.locked ||
            !_definition.fields.contains(field) ||
            (dependency != null && !shows(dependency))) {
          return;
        }
        Map<String, bool>? apply(Map<String, bool> latest) {
          final value =
              visible == field.defaultVisible && !field.retainExplicitDefault
              ? null
              : visible;
          if (latest[key] == value) return null;
          final next = {...latest};
          if (value == null) {
            next.remove(key);
          } else {
            next[key] = value;
          }
          return next;
        }

        if (_sessionOnly) {
          final next = apply(_snapshot.overrides);
          if (next != null) _publishLocal(next);
        } else {
          await _store?.edit(_definition.id, _owner!.scope, apply);
        }
      });
      _publish();
      await edit;
    } finally {
      if (_active(generation)) {
        _pendingKeys.remove(key);
        _publish();
      }
    }
  }

  void _publishLocal(Map<String, bool> overrides) {
    _snapshot = (
      overrides: Map.unmodifiable(overrides),
      revision: _snapshot.revision + 1,
      loaded: true,
      saving: false,
      failure: null,
    );
    _publish();
  }

  @override
  Future<void> resetToDefaults() async {
    if (_disposed ||
        _binding ||
        _resetting ||
        _retrying ||
        _snapshot.failure == FieldsFailure.load ||
        (!_sessionOnly && !_snapshot.loaded)) {
      return;
    }
    final generation = _generation;
    _resetting = true;
    try {
      final reset = _verifiedEdit(generation, () async {
        if (_sessionOnly) {
          _publishLocal(const {});
        } else {
          await _store?.reset(_definition.id, _owner!.scope);
        }
      });
      _publish();
      await reset;
    } finally {
      if (_active(generation)) {
        _resetting = false;
        _publish();
      }
    }
  }

  @override
  Future<void> retry() async {
    if (_disposed ||
        _binding ||
        _resetting ||
        _retrying ||
        _snapshot.failure == null ||
        _snapshot.saving) {
      return;
    }
    final generation = _generation;
    _retrying = true;
    _publish();
    try {
      await bind();
      if (_active(generation) && _owner != null) {
        await _store?.retry(_definition.id, _owner!);
      }
    } finally {
      if (_active(generation)) {
        _retrying = false;
        _publish();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _unwatchOwner?.call();
    _unwatchStore?.call();
    // Embedded results dispose during the same unmount as their Obx children.
    // Give those children a chance to cancel their GetX subscriptions first.
    scheduleMicrotask(state.close);
  }
}
