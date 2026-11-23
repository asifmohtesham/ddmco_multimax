import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/stock_entry_model.dart';

StockEntryItem row({
  String? source = 'WH-DXB1 - KA',
  String? target = 'WH-WIP1 - KA',
  int finished = 0,
  String? secondary,
  String? valuation,
}) => StockEntryItem(
  itemCode: '2003050',
  qty: 1,
  basicRate: 0,
  sWarehouse: source,
  tWarehouse: target,
  rack: 'KA-WH-DXB1-125B',
  toRack: 'KA-WH-WIP1-1A',
  isFinishedItem: finished,
  secondaryItemType: secondary,
  valuationType: valuation,
);

void main() {
  group('Stock Entry movement sides', () {
    for (final purpose in [
      'Material Issue',
      'Material Consumption for Manufacture',
    ]) {
      test(
        '$purpose checks the source and rejects a populated target rack',
        () {
          expect(row().movementSides(purpose), (source: true, target: false));
        },
      );
    }

    test('receipt checks the target only', () {
      expect(row().movementSides('Material Receipt'), (
        source: false,
        target: true,
      ));
    });

    for (final purpose in [
      'Material Transfer',
      'Material Transfer for Manufacture',
    ]) {
      test('$purpose checks both sides independently', () {
        expect(row().movementSides(purpose), (source: true, target: true));
      });
    }

    for (final purpose in ['Manufacture', 'Repack']) {
      test('$purpose separates consumption and all output roles', () {
        expect(row().movementSides(purpose), (source: true, target: false));
        for (final output in [
          row(finished: 1),
          row(secondary: 'Scrap'),
          row(valuation: 'Percentage'),
        ]) {
          expect(output.movementSides(purpose), (source: false, target: true));
          expect(
            output.toJson(purpose: purpose),
            containsPair('t_warehouse', output.tWarehouse),
          );
          expect(
            output.toJson(purpose: purpose),
            isNot(contains('s_warehouse')),
          );
        }
      });
    }

    test('Disassemble and custom movements use effective row sides', () {
      for (final purpose in [
        'Disassemble',
        'Custom movement',
        'Send to Subcontractor',
      ]) {
        expect(row(source: null).movementSides(purpose), (
          source: false,
          target: true,
        ));
        expect(row(target: null).movementSides(purpose), (
          source: true,
          target: false,
        ));
        expect(row().movementSides(purpose), (source: true, target: true));
      }
    });
  });

  group('Stock Entry row payload', () {
    test(
      'preserves the validated transfer target even with a source present',
      () {
        final doc = StockEntry.fromJson({
          'purpose': 'Material Transfer',
          'to_warehouse': 'WH-WIP3 - KA',
          'items': [row().toJson()],
        }).toJson();
        final item = (doc['items'] as List).single as Map<String, dynamic>;
        expect(doc['to_warehouse'], 'WH-WIP3 - KA');
        expect(item['s_warehouse'], 'WH-DXB1 - KA');
        expect(item['t_warehouse'], 'WH-WIP1 - KA');
        expect(item['rack'], 'KA-WH-DXB1-125B');
        expect(item['to_rack'], 'KA-WH-WIP1-1A');
      },
    );

    test(
      'preserves an existing rack on an inapplicable side for legacy repair',
      () {
        final json = row().toJson(purpose: 'Material Issue');
        expect(json, isNot(contains('t_warehouse')));
        expect(json['to_rack'], 'KA-WH-WIP1-1A');
      },
    );

    test(
      'round-trips secondary output role through header materialization',
      () {
        final original = StockEntryItem.fromJson({
          ...row().toJson(),
          'secondary_item_type': 'Scrap',
          'valuation_type': 'Percentage',
        });
        final output = original.withLocations(null, original.tWarehouse);
        final json = output.toJson(purpose: 'Manufacture');
        expect(json['secondary_item_type'], 'Scrap');
        expect(json['valuation_type'], 'Percentage');
        expect(json, isNot(contains('s_warehouse')));
      },
    );
  });
}
