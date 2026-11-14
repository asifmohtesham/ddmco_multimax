import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_price_model.dart';

void main() {
  group('parse helpers', () {
    test('pricingLink turns empty/null into null', () {
      expect(pricingLink(null), isNull);
      expect(pricingLink(''), isNull);
      expect(pricingLink('X'), 'X');
    });
    test('pricingDouble / pricingBool', () {
      expect(pricingDouble(3), 3.0);
      expect(pricingDouble('2.5'), 2.5);
      expect(pricingDouble(null), 0.0);
      expect(pricingBool(1), isTrue);
      expect(pricingBool('1'), isTrue);
      expect(pricingBool(0), isFalse);
    });
    test('pricingScrub', () {
      expect(pricingScrub('Customer Group'), 'customer_group');
    });
  });

  group('ItemPrice', () {
    final json = {
      'name': '5dfs7bls6g',
      'item_code': '1000001',
      'item_name': 'WALLETS COW',
      'uom': 'Nos',
      'packing_unit': 0,
      'price_list': 'Standard Selling',
      'customer': null,
      'supplier': '',
      'batch_no': null,
      'buying': 0,
      'selling': 1,
      'currency': 'AED',
      'price_list_rate': 25,
      'valid_from': '2026-04-22',
      'valid_upto': null,
      'lead_time_days': 0,
      'note': null,
      'brand': null,
      'reference': null,
      'modified': '2026-04-22 17:36:55.939816',
    };

    test('fromJson reads every field', () {
      final p = ItemPrice.fromJson(json);
      expect(p.name, '5dfs7bls6g');
      expect(p.itemCode, '1000001');
      expect(p.itemName, 'WALLETS COW');
      expect(p.selling, isTrue);
      expect(p.buying, isFalse);
      expect(p.rate, 25.0);
      expect(p.supplier, isNull);
      expect(p.validFrom, '2026-04-22');
      expect(p.modified, '2026-04-22 17:36:55.939816');
    });

    test('toJson sends only the client-settable fields', () {
      final out = ItemPrice.fromJson(json).toJson();
      expect(out.keys.toSet(), {
        'item_code', 'uom', 'packing_unit', 'price_list', 'customer',
        'supplier', 'batch_no', 'price_list_rate', 'valid_from',
        'valid_upto', 'lead_time_days', 'note',
      });
      expect(out['supplier'], isNull);
      expect(out['price_list_rate'], 25.0);
    });

    test('PriceListInfo.kind', () {
      final l = PriceListInfo.fromJson(
          {'name': 'Standard Buying', 'currency': 'AED', 'buying': 1, 'selling': 0});
      expect(l.kind, 'Buying');
      expect(l.buying, isTrue);
    });
  });
}
