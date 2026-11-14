import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/item_model.dart';

void main() {
  test('Item.hasVariants reads has_variants', () {
    expect(Item.fromJson({'name': 'T', 'has_variants': 1}).hasVariants, isTrue);
    expect(Item.fromJson({'name': 'V', 'has_variants': 0}).hasVariants, isFalse);
    expect(Item.fromJson({'name': 'X'}).hasVariants, isFalse);
  });
}
