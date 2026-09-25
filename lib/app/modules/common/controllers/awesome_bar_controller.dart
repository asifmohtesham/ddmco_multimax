import 'package:get/get.dart';
import 'package:multimax/app/data/providers/search_provider.dart';
import 'package:multimax/app/utils/fuzzy_search.dart';
import 'package:math_expressions/math_expressions.dart';
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
  
  AwesomeBarOption({
    required this.type,
    required this.label,
    required this.value,
    this.index = 0,
    required this.route,
    this.routeOptions,
    this.description,
    this.isGlobalSearch = false,
  });
}

class AwesomeBarController extends GetxController {
  final SearchProvider _searchProvider = Get.put(SearchProvider());
  
  final options = <AwesomeBarOption>[].obs;
  final isLoading = false.obs;
  
  Timer? _debounce;
  
  List<String> canRead = [];
  List<String> canSearch = [];
  List<String> canCreate = [];
  Map<String, dynamic> workspaces = {};
  
  @override
  void onInit() {
    super.onInit();
    _fetchBootData();
  }
  
  Future<void> _fetchBootData() async {
    try {
      final response = await _searchProvider.getBootData();
      if (response.data != null && response.data['message'] != null) {
        final bootData = response.data['message'];
        
        final user = bootData['user'];
        if (user != null) {
          canRead = List<String>.from(user['can_read'] ?? []);
          canSearch = List<String>.from(user['can_search'] ?? []);
          canCreate = List<String>.from(user['can_create'] ?? []);
        }
        
        workspaces = bootData['workspaces'] ?? {};
      }
    } catch (e) {
      print('Failed to fetch boot data for Awesome Bar: $e');
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
    
    // 3. Backend Hooks (awesomebar_search)
    try {
      final hookResponse = await _searchProvider.awesomeBarSearch(query);
      if (hookResponse.data != null && hookResponse.data['message'] != null) {
        final List hookItems = hookResponse.data['message'];
        for (var item in hookItems) {
          results.add(AwesomeBarOption(
            type: item['type'] ?? 'Hook',
            label: item['label'] ?? item['value'],
            value: item['value'] ?? '',
            index: item['index'] ?? 0,
            route: item['route'] is List ? item['route'].join('/') : (item['route'] ?? ''),
            description: item['description'],
          ));
        }
      }
    } catch (e) {
      print('Hook search failed: $e');
    }
    
    // 4. Global Search Results
    try {
      final globalResponse = await _searchProvider.globalSearch(query);
      if (globalResponse.data != null && globalResponse.data['message'] != null) {
        final List globalItems = globalResponse.data['message'];
        for (var item in globalItems) {
          results.add(AwesomeBarOption(
            type: 'Search Result',
            label: item['title'] ?? item['name'],
            value: item['name'],
            description: item['content'],
            route: '/app/\${item['doctype']}/\${item['name']}',
            isGlobalSearch: true,
          ));
        }
      }
    } catch (e) {
      print('Global search failed: $e');
    }
    
    // Sort and Update
    results.sort((a, b) => b.index.compareTo(a.index)); // Descending score
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
          label: '$exprString = $eval',
          value: eval.toString(),
          route: '',
          index: 1000,
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
      for (var doctype in canCreate) {
        final match = FuzzySearch.fuzzyMatch(doctypeQuery, doctype, returnMarkedString: true);
        if (match.score > 0) {
          results.add(AwesomeBarOption(
            type: 'New',
            label: 'New ${match.markedString}',
            value: 'New $doctype',
            index: match.score + 100,
            route: '/app/$doctype/new',
          ));
        }
      }
    }
    
    // Doctype Lists
    for (var doctype in canRead) {
      if (canSearch.contains(doctype)) {
        final match = FuzzySearch.fuzzyMatch(query, doctype, returnMarkedString: true);
        if (match.score > 0) {
          results.add(AwesomeBarOption(
            type: 'List',
            label: '${match.markedString} List',
            value: '$doctype List',
            index: match.score,
            route: '/app/$doctype',
          ));
        }
      }
    }
    
    return results;
  }
  
  void onOptionSelected(AwesomeBarOption option) {
    if (option.type == 'Calculator') {
      Get.snackbar('Result', option.value);
      return;
    }
    if (option.route.isNotEmpty) {
      Get.toNamed(option.route); // Example routing logic, adjust to app's route format
    }
  }
}
