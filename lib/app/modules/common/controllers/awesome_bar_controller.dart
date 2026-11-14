import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  Map<String, dynamic> toJson() => {
    'type': type,
    'label': label,
    'value': value,
    'route': route,
    'routeOptions': routeOptions,
    'description': description,
    'isGlobalSearch': isGlobalSearch,
  };

  factory AwesomeBarOption.fromJson(Map<String, dynamic> json) {
    return AwesomeBarOption(
      type: json['type'] ?? '',
      label: json['label'] ?? '',
      value: json['value'] ?? '',
      route: json['route'] ?? '',
      routeOptions: json['routeOptions'] != null ? Map<String, dynamic>.from(json['routeOptions']) : null,
      description: json['description'],
      isGlobalSearch: json['isGlobalSearch'] ?? false,
    );
  }
}

class AwesomeBarController extends GetxController {
  final SearchProvider _searchProvider = Get.put(SearchProvider());
  
  final options = <AwesomeBarOption>[].obs;
  final recentOptions = <AwesomeBarOption>[].obs;
  final isLoading = false.obs;
  
  Timer? _debounce;
  
  @override
  void onInit() {
    super.onInit();
    _loadRecents();
  }
  
  Future<void> _loadRecents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentsJson = prefs.getStringList('awesome_bar_recents') ?? [];
      final List<AwesomeBarOption> loaded = [];
      for (var str in recentsJson) {
        final opt = AwesomeBarOption.fromJson(jsonDecode(str));
        loaded.add(_enrichWithIcon(opt));
      }
      recentOptions.value = loaded;
    } catch (e) {
      print('Failed to load recent searches: $e');
    }
  }

  Future<void> _saveRecent(AwesomeBarOption option) async {
    // Don't save calculator results
    if (option.type == 'Calculator') return;

    try {
      final prefs = await SharedPreferences.getInstance();
      // Remove if exists to put it at the top
      recentOptions.removeWhere((o) => o.value == option.value && o.route == option.route);
      recentOptions.insert(0, option);
      // Keep only last 5
      if (recentOptions.length > 5) {
        recentOptions.removeLast();
      }
      
      final List<String> encoded = recentOptions.map((o) => jsonEncode(o.toJson())).toList();
      await prefs.setStringList('awesome_bar_recents', encoded);
    } catch (e) {
      print('Failed to save recent search: $e');
    }
  }

  void onSearchQueryChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.trim().isEmpty) {
      options.clear();
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query.trim());
    });
  }
  
  AwesomeBarOption _enrichWithIcon(AwesomeBarOption opt) {
    final target = searchTargetForDoctype(opt.type == 'Search Result' ? '' : opt.type);
    if (target != null) {
      return AwesomeBarOption(
        type: opt.type,
        label: opt.label,
        value: opt.value,
        index: opt.index,
        route: opt.route,
        description: opt.description,
        isGlobalSearch: opt.isGlobalSearch,
        icon: target.icon,
        color: target.color,
      );
    }
    return opt;
  }

  Future<void> _performSearch(String query) async {
    isLoading.value = true;
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
      final globalResponse = await _searchProvider.globalSearch(query);
      if (globalResponse.data != null && globalResponse.data['message'] != null) {
        final List globalItems = globalResponse.data['message'];
        for (var item in globalItems) {
          String description = item['content'] ?? '';
          description = description.replaceAll(' ||| ', ' • ');
          
          final opt = AwesomeBarOption(
            type: item['doctype'] ?? 'Search Result',
            label: item['title'] ?? item['name'],
            value: item['name'],
            description: description,
            route: "/app/${item['doctype']}/${item['name']}",
            isGlobalSearch: true,
          );
          results.add(_enrichWithIcon(opt));
        }
      }
    } catch (e) {
      print('Global search failed: $e');
    }
    
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
    _saveRecent(option);
    
    if (option.type == 'Calculator') {
      Get.snackbar('Result', option.value);
      return;
    }
    if (option.route.isNotEmpty) {
      Get.toNamed(option.route, arguments: option.routeOptions);
    }
  }
}
