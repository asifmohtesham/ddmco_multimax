import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:multimax/app/data/providers/search_provider.dart';
import 'package:multimax/app/modules/common/services/awesome_bar_recent_store.dart';
import 'package:multimax/app/utils/fuzzy_search.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';

export 'package:multimax/app/modules/common/services/awesome_bar_recent_store.dart';

class AwesomeBarController extends GetxController {
  AwesomeBarController({Future<Response> Function(String)? globalSearch})
    : _globalSearch = globalSearch ?? SearchProvider().globalSearch;

  final Future<Response> Function(String) _globalSearch;
  
  final options = <AwesomeBarOption>[].obs;
  final recentOptions = <AwesomeBarOption>[].obs;
  final isLoading = false.obs;
  
  Timer? _debounce;
  int _searchSequence = 0;
  String? _completedQuery;
  String? _submittedQuery;
  StreamSubscription<List<AwesomeBarOption>>? _recentSubscription;
  
  @override
  void onInit() {
    super.onInit();
    _recentSubscription = AwesomeBarRecentStore.changes.listen(
      recentOptions.assignAll,
    );
    unawaited(_loadRecents());
  }

  @override
  void onClose() {
    _debounce?.cancel();
    _searchSequence++;
    unawaited(_recentSubscription?.cancel());
    _recentSubscription = null;
    super.onClose();
  }
  
  Future<void> _loadRecents() async {
    final loaded = await AwesomeBarRecentStore.read();
    if (_recentSubscription != null) recentOptions.assignAll(loaded);
  }

  void onSearchQueryChanged(String query) {
    _debounce?.cancel();
    final sequence = ++_searchSequence;
    final trimmedQuery = query.trim();
    if (trimmedQuery != _submittedQuery) _submittedQuery = null;
    _completedQuery = null;
    // Previous results stay on screen until the new ones arrive, so the list
    // doesn't flash empty on every keystroke.
    isLoading.value = trimmedQuery.isNotEmpty;
    if (trimmedQuery.isEmpty) {
      options.clear();
      return;
    }

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
    var searchFailed = false;
    try {
      final globalResponse = await _globalSearch(query);
      if (sequence != _searchSequence) return;
      if (globalResponse.data != null && globalResponse.data['message'] != null) {
        final List globalItems = globalResponse.data['message'];
        for (var item in globalItems) {
          final opt = AwesomeBarOption.fromGlobalSearchHit(item);
          if (opt != null) results.add(opt);
        }
      }
    } catch (e) {
      debugPrint('Global search failed: $e');
      searchFailed = true;
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
    // A failed request isn't "no results", so it is never saved.
    _completedQuery = searchFailed ? null : query;
    if (_submittedQuery == query && !searchFailed) _saveIfNothingFound(query);
  }

  /// The keyboard's search key commits the query. One that finds nothing is
  /// saved to RECENT so it can be tried again later.
  void onQuerySubmitted(String text) {
    final query = text.trim();
    if (query.isEmpty) return;
    _submittedQuery = query;
    if (_completedQuery == query) _saveIfNothingFound(query);
  }

  void _saveIfNothingFound(String query) {
    _submittedQuery = null;
    if (options.isNotEmpty) return;
    unawaited(AwesomeBarRecentStore.record(AwesomeBarOption.query(query)));
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
    if (option.isScan || option.isQuery) return;
    if (option.type == 'Calculator') {
      Get.snackbar('Result', option.value);
      return;
    }
    final resolved = option.resolveNavigation();
    if (resolved == null) return;
    unawaited(AwesomeBarRecentStore.record(resolved));
    if (resolved.route.isNotEmpty) {
      Get.toNamed(resolved.route, arguments: resolved.routeOptions);
    }
  }
}
