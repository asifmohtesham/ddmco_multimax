import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/recent_searches.dart';
import 'package:multimax/app/data/services/storage_service.dart';

import '../support/recent_search_test_box.dart';

void main() {
  group('RecentSearches', () {
    test('normalizes whitespace and keeps the latest casing and position', () {
      final current = ['Order', 'blue widget'];
      expect(RecentSearches.add(current, '  BLUE\t  Widget\n '), [
        'BLUE Widget',
        'Order',
      ]);
      expect(current, ['Order', 'blue widget']);
    });

    test('keeps the ten most recent terms', () {
      var history = <String>[];
      for (var i = 0; i < 11; i++) {
        history = RecentSearches.add(history, 'Order $i');
      }
      expect(history, List.generate(10, (i) => 'Order ${10 - i}'));
    });

    test('ignores empty and short terms after normalization', () {
      final current = ['Order'];
      expect(RecentSearches.add(current, '\n \t'), current);
      expect(RecentSearches.add(current, '  AB ', minLength: 3), current);
      expect(RecentSearches.add(current, 'A'), ['A', 'Order']);
    });

    test('removes case-insensitively and clears', () {
      expect(
        RecentSearches.remove(['Order', 'Blue Widget'], ' blue   widget '),
        ['Order'],
      );
      expect(RecentSearches.clear(), isEmpty);
    });
  });

  test(
    'StorageService isolates contexts and users and retains history on logout',
    () async {
      final box = RecentSearchTestBox();
      final storage = StorageService.withStorage(box);
      const alice = 'alice@example.com';
      const bob = 'bob@example.com';

      await storage.addRecentSearch('Sales Order', alice, 'SO-1');
      expect(box.data['recent_searches::Sales Order::$alice'], ['SO-1']);
      expect(storage.getRecentSearches('Sales Order', bob), isEmpty);
      expect(storage.getRecentSearches('Item', alice), isEmpty);

      await storage.addRecentSearch('Sales Order', bob, 'SO-2');
      await storage.addRecentSearch('Item', alice, 'Widget');
      await storage.clearUserData();
      expect(storage.getRecentSearches('Sales Order', alice), ['SO-1']);

      await storage.addRecentSearch('Sales Order', alice, 'SO-3');
      await storage.removeRecentSearch('Sales Order', alice, 'so-3');
      expect(storage.getRecentSearches('Sales Order', alice), ['SO-1']);
      await storage.clearRecentSearches('Sales Order', alice);
      expect(storage.getRecentSearches('Sales Order', alice), isEmpty);
      expect(storage.getRecentSearches('Sales Order', bob), ['SO-2']);
      expect(storage.getRecentSearches('Item', alice), ['Widget']);
    },
  );
}
