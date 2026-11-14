import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

// ERPNext v15.72.0 turned the Stock Balance report's item_code filter into a
// MultiSelectList; from then on a bare string makes the report fail. The old
// check compared only the minor number, so v16.x (minor < 72) got the string
// form and the report 500'd ("'str' object has no attribute 'nodes_'") —
// which the rack picker showed as "No racks found with stock".
void main() {
  group('ApiProvider.stockBalanceUsesListFilters', () {
    test('v15 before 15.72 uses a plain string', () {
      expect(ApiProvider.stockBalanceUsesListFilters('15.71.3'), isFalse);
      expect(ApiProvider.stockBalanceUsesListFilters('15.0.0'), isFalse);
    });

    test('v15.72 and later v15 use a list', () {
      expect(ApiProvider.stockBalanceUsesListFilters('15.72.0'), isTrue);
      expect(ApiProvider.stockBalanceUsesListFilters('15.121.1'), isTrue);
    });

    test('every v16+ uses a list, whatever its minor number', () {
      expect(ApiProvider.stockBalanceUsesListFilters('16.26.2'), isTrue);
      expect(ApiProvider.stockBalanceUsesListFilters('16.0.0'), isTrue);
      expect(ApiProvider.stockBalanceUsesListFilters('17.1.0'), isTrue);
    });

    test('older majors use a plain string', () {
      expect(ApiProvider.stockBalanceUsesListFilters('14.99.0'), isFalse);
    });

    test('unknown or unparsable version assumes the current (list) form', () {
      expect(ApiProvider.stockBalanceUsesListFilters(null), isTrue);
      expect(ApiProvider.stockBalanceUsesListFilters(''), isTrue);
      expect(ApiProvider.stockBalanceUsesListFilters('develop'), isTrue);
    });

    test('pre-release suffixes are tolerated', () {
      expect(ApiProvider.stockBalanceUsesListFilters('16.0.0-beta.3'), isTrue);
      expect(ApiProvider.stockBalanceUsesListFilters('15.72.0-dev'), isTrue);
    });
  });
}
