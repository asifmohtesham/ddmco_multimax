import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/search_provider.dart';
import 'package:multimax/app/utils/fuzzy_search.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

class AwesomeBarOption {
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
  });

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
    ).resolveNavigation();
  }

  /// Supplies the form destination for fresh hits and older saved recents.
  AwesomeBarOption? resolveNavigation() {
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
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    'label': label,
    'value': value,
    'route': route,
    'routeOptions': routeOptions,
    'description': description,
    'isGlobalSearch': isGlobalSearch,
  };

  AwesomeBarOption _enrichWithIcon() {
    final doctype = switch (type) {
      'List' when value.endsWith(' List') =>
        value.substring(0, value.length - ' List'.length),
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
    return AwesomeBarOption(
      type: json['type'] ?? '',
      label: json['label'] ?? '',
      value: json['value'] ?? '',
      route: json['route'] ?? '',
      routeOptions: json['routeOptions'] != null ? Map<String, dynamic>.from(json['routeOptions']) : null,
      description: json['description'],
      isGlobalSearch: json['isGlobalSearch'] ?? false,
    )._enrichWithIcon();
  }
}

class AwesomeBarController extends GetxController {
  AwesomeBarController({Future<Response> Function(String)? globalSearch})
    : _globalSearch = globalSearch ?? SearchProvider().globalSearch;

  final Future<Response> Function(String) _globalSearch;
  
  final options = <AwesomeBarOption>[].obs;
  final recentOptions = <AwesomeBarOption>[].obs;
  final isLoading = false.obs;
  
  Timer? _debounce;
  int _searchSequence = 0;
  
  @override
  void onInit() {
    super.onInit();
    _loadRecents();
  }

  @override
  void onClose() {
    _debounce?.cancel();
    _searchSequence++;
    super.onClose();
  }
  
  Future<void> _loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentsJson = prefs.getStringList('awesome_bar_recents') ?? [];
      final List<AwesomeBarOption> loaded = [];
      for (final str in recentsJson) {
        try {
          final opt = AwesomeBarOption.fromJson(jsonDecode(str));
          if (opt.resolveNavigation() != null) loaded.add(opt);
        } catch (e) {
          debugPrint('Skipping invalid AwesomeBar recent: $e');
        }
      }
      recentOptions.value = loaded;
    } catch (e) {
      debugPrint('Failed to load recent searches: $e');
    }
  }

  Future<void> _saveRecent(AwesomeBarOption option) async {
    // Don't save calculator results
    if (option.type == 'Calculator') return;

    try {
      final prefs = await SharedPreferences.getInstance();
      // Remove if exists to put it at the top
      recentOptions.removeWhere(
        (o) => o.value == option.value &&
            o.resolveNavigation()?.route == option.route,
      );
      recentOptions.insert(0, option);
      // Keep only last 5
      if (recentOptions.length > 5) {
        recentOptions.removeLast();
      }
      
      final List<String> encoded = recentOptions.map((o) => jsonEncode(o.toJson())).toList();
      await prefs.setStringList('awesome_bar_recents', encoded);
    } catch (e) {
      debugPrint('Failed to save recent search: $e');
    }
  }

  void onSearchQueryChanged(String query) {
    _debounce?.cancel();
    final sequence = ++_searchSequence;
    final trimmedQuery = query.trim();
    isLoading.value = trimmedQuery.isNotEmpty;
    options.clear();
    if (trimmedQuery.isEmpty) return;

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(trimmedQuery, sequence);
    });
  }
  
  Future<void> _performSearch(String query, int sequence) async {
    final List<AwesomeBarOption> results = [];
    
    // 1. Math Evaluator
    final mathResult = _evaluateMathExpression(query);
    if (mathResult != null) {
      results.add(mathResult);
    }
    
    // 2. Client-side Navigation Options
    results.addAll(_getLocalSearchOptions(query));
    
    // 3. Global Search Results
    try {
      final globalResponse = await _globalSearch(query);
      if (sequence != _searchSequence) return;
      if (globalResponse.data != null && globalResponse.data['message'] != null) {
        final List globalItems = globalResponse.data['message'];
        for (var item in globalItems) {
          final opt = AwesomeBarOption.fromGlobalSearchHit(item);
          if (opt != null) results.add(opt._enrichWithIcon());
        }
      }
    } catch (e) {
      debugPrint('Global search failed: $e');
    }
    
    if (sequence != _searchSequence) return;

    // Sort and Update
    results.sort((a, b) {
      int cmp = b.index.compareTo(a.index);
      if (cmp == 0) {
        return a.type.compareTo(b.type);
      }
      return cmp;
    });
    options.value = results;
    isLoading.value = false;
  }
  
  AwesomeBarOption? _evaluateMathExpression(String query) {
    if (query.startsWith('=') || double.tryParse(query.substring(0, 1)) != null || query.startsWith('(')) {
      try {
        final exprString = query.startsWith('=') ? query.substring(1) : query;
        Parser p = Parser();
        Expression exp = p.parse(exprString);
        ContextModel cm = ContextModel();
        double eval = exp.evaluate(EvaluationType.REAL, cm);
        
        return AwesomeBarOption(
          type: 'Calculator',
          label: '$exprString = <b>$eval</b>',
          value: eval.toString(),
          route: '',
          index: 1000,
          icon: Icons.calculate_outlined,
          color: Colors.blueGrey,
        );
      } catch (e) {
        // Not a valid math expression
        return null;
      }
    }
    return null;
  }
  
  List<AwesomeBarOption> _getLocalSearchOptions(String query) {
    List<AwesomeBarOption> results = [];
    
    // Create new
    if (query.toLowerCase().startsWith('new ')) {
      final doctypeQuery = query.substring(4);
      for (var target in kDiscoverableSearchTargets) {
        final match = FuzzySearch.fuzzyMatch(doctypeQuery, target.doctype, returnMarkedString: true);
        if (match.score > 0) {
          results.add(AwesomeBarOption(
            type: 'New',
            label: 'New ${match.markedString}',
            value: 'New ${target.doctype}',
            index: match.score + 100,
            route: target.route,
            routeOptions: {'mode': 'new'},
            icon: Icons.add_circle_outline,
            color: target.color,
          ));
        }
      }
    }
    
    // Doctype Lists
    for (var target in kDiscoverableSearchTargets) {
      final match = FuzzySearch.fuzzyMatch(query, target.doctype, returnMarkedString: true);
      if (match.score > 0) {
        results.add(AwesomeBarOption(
          type: 'List',
          label: '${match.markedString} List',
          value: '${target.doctype} List',
          index: match.score,
          route: target.route.replaceAll('/form', ''),
          icon: target.icon,
          color: target.color,
        ));
      }
    }
    
    return results;
  }
  
  void onOptionSelected(AwesomeBarOption option) {
    if (option.type == 'Calculator') {
      Get.snackbar('Result', option.value);
      return;
    }
    final resolved = option.resolveNavigation();
    if (resolved == null) return;
    _saveRecent(resolved);
    if (resolved.route.isNotEmpty) {
      Get.toNamed(resolved.route, arguments: resolved.routeOptions);
    }
  }
}
