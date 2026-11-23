import 'dart:async';
import 'dart:convert';

// Keep the shared Flutter Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/scan_result_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AwesomeBarOption {
  static const _scanType = 'Scan';

  final String type;
  final String label;
  final String value;
  final int index;
  final String route;
  final Map<String, dynamic>? routeOptions;
  final String? description;
  final bool isGlobalSearch;
  final IconData? icon;
  final Color? color;
  final ScanType? scanKind;
  final ScanOutcome? scanOutcome;

  AwesomeBarOption({
    required this.type,
    required this.label,
    required this.value,
    this.index = 0,
    required this.route,
    this.routeOptions,
    this.description,
    this.isGlobalSearch = false,
    this.icon,
    this.color,
    this.scanKind,
    this.scanOutcome,
  });

  bool get isScan => type == _scanType;

  factory AwesomeBarOption.scan({
    required String code,
    required ScanType kind,
    required ScanOutcome outcome,
    String? itemLabel,
    String? rackId,
  }) {
    final displayCode = code.trim();
    final label = switch (kind) {
      ScanType.item || ScanType.batch =>
        itemLabel == null || itemLabel.trim().isEmpty ? displayCode : itemLabel,
      ScanType.rack => 'Rack ${rackId ?? displayCode}',
      ScanType.variant_of => 'Variants of $displayCode',
      ScanType.multiple => 'Multiple items',
      ScanType.unknown || ScanType.error => displayCode,
    };

    return AwesomeBarOption(
      type: _scanType,
      label: label,
      value: code,
      route: '',
      description: _scanDescription(code, outcome),
      scanKind: kind,
      scanOutcome: outcome,
    )._enrichWithIcon();
  }

  static String _scanDescription(String code, ScanOutcome outcome) =>
      switch (outcome) {
        ScanOutcome.ok => 'Scanned ${code.trim()}',
        ScanOutcome.notFound => 'Not found',
        ScanOutcome.invalid => 'Invalid rack code',
        ScanOutcome.empty => 'Empty rack',
        ScanOutcome.error => 'Scan failed',
      };

  static AwesomeBarOption? fromGlobalSearchHit(Map<String, dynamic> hit) {
    final name = hit['name'];
    final doctype = hit['doctype'];
    if (name is! String || doctype is! String) return null;

    return AwesomeBarOption(
      type: doctype,
      label: hit['title'] ?? name,
      value: name,
      description: (hit['content'] as String? ?? '').replaceAll(' ||| ', ' • '),
      route: '',
      isGlobalSearch: true,
    ).resolveNavigation()?._enrichWithIcon();
  }

  /// Supplies the form destination for fresh hits and older saved recents.
  AwesomeBarOption? resolveNavigation() {
    if (isScan) {
      return value.trim().isNotEmpty && scanKind != null && scanOutcome != null
          ? this
          : null;
    }
    if (route.isNotEmpty && !route.startsWith('/app/')) return this;
    if (!isGlobalSearch && type == 'Calculator') return this;

    final target = searchTargetForDoctype(type);
    if (target == null || value.isEmpty) return null;
    return _copyWith(route: target.route, routeOptions: target.argsFor(value));
  }

  AwesomeBarOption _copyWith({
    String? route,
    Map<String, dynamic>? routeOptions,
    IconData? icon,
    Color? color,
  }) => AwesomeBarOption(
    type: type,
    label: label,
    value: value,
    index: index,
    route: route ?? this.route,
    routeOptions: routeOptions ?? this.routeOptions,
    description: description,
    isGlobalSearch: isGlobalSearch,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    scanKind: scanKind,
    scanOutcome: scanOutcome,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'label': label,
    'value': value,
    'route': route,
    'routeOptions': routeOptions,
    'description': description,
    'isGlobalSearch': isGlobalSearch,
    if (scanKind case final kind?) 'scanKind': kind.name,
    if (scanOutcome case final outcome?)
      'outcome': outcome == ScanOutcome.notFound ? 'not_found' : outcome.name,
  };

  AwesomeBarOption _enrichWithIcon() {
    if (isScan) {
      final itemTarget = searchTargetForDoctype('Item');
      return switch (scanKind) {
        ScanType.item || ScanType.batch => _copyWith(
          icon: itemTarget?.icon,
          color: itemTarget?.color,
        ),
        ScanType.rack => _copyWith(icon: Icons.shelves),
        ScanType.variant_of => _copyWith(icon: Icons.account_tree_outlined),
        ScanType.multiple => _copyWith(icon: Icons.list_alt_outlined),
        _ => _copyWith(icon: Icons.qr_code_scanner),
      };
    }

    final doctype = switch (type) {
      'List' when value.endsWith(' List') => value.substring(
        0,
        value.length - ' List'.length,
      ),
      'New' when value.startsWith('New ') => value.substring('New '.length),
      _ => type,
    };
    final target = searchTargetForDoctype(doctype);
    if (target == null) return this;
    return _copyWith(
      icon: type == 'New' ? Icons.add_circle_outline : target.icon,
      color: target.color,
    );
  }

  factory AwesomeBarOption.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    final value = json['value'] as String? ?? '';
    final outcome = switch (json['outcome']) {
      'not_found' => ScanOutcome.notFound,
      final String name => ScanOutcome.values.byName(name),
      _ => null,
    };
    return AwesomeBarOption(
      type: type,
      label: json['label'] as String? ?? '',
      value: value,
      route: json['route'] as String? ?? '',
      routeOptions: json['routeOptions'] != null
          ? Map<String, dynamic>.from(json['routeOptions'])
          : null,
      description: outcome == null
          ? json['description'] as String?
          : _scanDescription(value, outcome),
      isGlobalSearch: json['isGlobalSearch'] as bool? ?? false,
      scanKind: type == _scanType
          ? ScanType.values.byName(json['scanKind'] as String)
          : null,
      scanOutcome: outcome,
    )._enrichWithIcon();
  }

  bool _duplicates(AwesomeBarOption other) {
    if (isScan != other.isScan) return false;
    if (isScan) {
      return value.trim().toLowerCase() == other.value.trim().toLowerCase();
    }
    return value == other.value && resolveNavigation()?.route == other.route;
  }
}

/// Dashboard scans and AwesomeBar picks share the same on-device history.
class AwesomeBarRecentStore {
  static const _preferencesKey = 'awesome_bar_recents';
  static const int capacity = 10;

  static Future<void>? _pendingRecord;
  static final _changes = StreamController<List<AwesomeBarOption>>.broadcast();
  static int _scanRevision = 0;

  static Stream<List<AwesomeBarOption>> get changes => _changes.stream;

  /// Changes after each scan, including when a repeat has the same outcome.
  static int get scanRevision => _scanRevision;

  static Future<List<AwesomeBarOption>> read() async {
    await _pendingRecord;
    try {
      return _read(await SharedPreferences.getInstance());
    } catch (e) {
      debugPrint('Failed to load recent searches: $e');
      return [];
    }
  }

  static Future<void> record(AwesomeBarOption option) {
    final resolved = option.resolveNavigation();
    if (resolved == null || resolved.type == 'Calculator') {
      return Future<void>.value();
    }

    // Serialize the entire read-modify-write so scans and picks cannot lose
    // one another's updates, even while the overlay is being reopened.
    late final Future<void> pending;
    pending = Future<void>.value(_pendingRecord)
        .then((_) async {
          try {
            final prefs = await SharedPreferences.getInstance();
            final recents = [
              resolved,
              ..._read(prefs).where((recent) => !recent._duplicates(resolved)),
            ].take(capacity).toList(growable: false);
            final encoded = recents.map(
              (option) => jsonEncode(option.toJson()),
            );
            if (!await prefs.setStringList(_preferencesKey, encoded.toList())) {
              debugPrint('Failed to persist AwesomeBar recent search');
            }
            if (resolved.isScan) _scanRevision++;
            _changes.add(recents);
          } catch (e) {
            debugPrint('Failed to save recent search: $e');
          }
        })
        .whenComplete(() {
          if (identical(_pendingRecord, pending)) _pendingRecord = null;
        });
    return _pendingRecord = pending;
  }

  static List<AwesomeBarOption> _read(SharedPreferences prefs) {
    final loaded = <AwesomeBarOption>[];
    for (final encoded in prefs.getStringList(_preferencesKey) ?? <String>[]) {
      try {
        final option = AwesomeBarOption.fromJson(jsonDecode(encoded));
        if (option.resolveNavigation() != null) loaded.add(option);
        if (loaded.length == capacity) break;
      } catch (e) {
        debugPrint('Skipping invalid AwesomeBar recent: $e');
      }
    }
    return loaded;
  }
}
