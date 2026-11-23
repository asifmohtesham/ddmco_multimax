import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/shared/item_sheet/rack_warehouse_rule.dart';

const _company = 'K A';
const _wip = 'WH-WIP1 - KA';
const _dxb = 'WH-DXB1 - KA';
const _rack = 'KA-WH-WIP1-1A';

RackWarehouse _warehouse(
  String name,
  String warehouseName, {
  String company = _company,
  bool group = false,
  bool disabled = false,
}) => RackWarehouse(
  name: name,
  warehouseName: warehouseName,
  company: company,
  isGroup: group,
  disabled: disabled,
);

void main() {
  group('Rack pair verdict', () {
    test('canonical rack and exact same-side warehouse in refusal', () {
      final verdict = evaluateRackPair(
        rack: _rack,
        side: RackSide.source,
        rackWarehouse: _wip,
        rowWarehouse: _dxb,
      );
      expect(verdict.issue, RackPairIssue.mismatch);
      expect(
        verdict.message,
        'Rack KA-WH-WIP1-1A belongs to WH-WIP1 - KA. '
        'This row’s source warehouse is WH-DXB1 - KA.',
      );
      expect(verdict.savedMessage, 'Saved rack${verdict.message.substring(4)}');
    });

    test('a sibling warehouse still mismatches', () {
      expect(
        evaluateRackPair(
          rack: _rack,
          side: RackSide.target,
          rackWarehouse: _wip,
          rowWarehouse: 'WH-WIP3 - KA',
        ).issue,
        RackPairIssue.mismatch,
      );
    });

    test('optional blank skips matching and a stray rack is refused', () {
      expect(
        evaluateRackPair(
          rack: '',
          side: RackSide.target,
          applicable: false,
        ).isValid,
        isTrue,
      );
      expect(
        evaluateRackPair(
          rack: _rack,
          side: RackSide.target,
          applicable: false,
        ).message,
        'This row has no target warehouse. Clear rack $_rack.',
      );
    });

    test('initialization replaces defaults but only when enabled', () {
      for (final input in [_dxb, null]) {
        final verdict = evaluateRackPair(
          rack: _rack,
          side: RackSide.outbound,
          rackWarehouse: _wip,
          rowWarehouse: input,
          initializeWarehouse: true,
        );
        expect(verdict.isValid, isTrue);
        expect(verdict.rowWarehouse, _wip);
      }
      expect(
        evaluateRackPair(
          rack: _rack,
          side: RackSide.target,
          rackWarehouse: _wip,
        ).issue,
        RackPairIssue.warehouseRequired,
      );
      expect(
        evaluateRackPair(
          rack: _rack,
          side: RackSide.target,
          rackWarehouse: _wip,
          lookupIssue: RackPairIssue.unavailable,
          rowWarehouse: _dxb,
          initializeWarehouse: true,
        ).rowWarehouse,
        _dxb,
      );
    });
  });

  group('Canonical aliases and blank-link fallback', () {
    test('only the document company suffix can be stripped', () {
      expect(rackAlias('$_rack - KA', 'KA'), _rack);
      expect(rackAlias('$_rack - XX', 'KA'), isNull);
      expect(rackAlias('$_rack - KA', null), isNull);
    });

    test('longest active leaf prefix wins and slot spaces are supported', () {
      expect(
        warehouseFromRackPrefix(
          rack: 'KA-POS-DXB1-SECTION A-SLOT 22',
          company: _company,
          abbreviation: 'KA',
          warehouses: [
            _warehouse('POS - KA', 'POS'),
            _warehouse('POS-DXB1 - KA', 'POS-DXB1'),
            _warehouse('SECTION A - KA', 'POS-DXB1-SECTION A'),
          ],
        ),
        'SECTION A - KA',
      );
    });

    test(
      'ambiguous, blank slot, cross-company, disabled and group mappings',
      () {
        for (final warehouses in [
          [_warehouse('A', 'WH-WIP1'), _warehouse('B', 'WH-WIP1')],
          [_warehouse(_wip, 'WH-WIP1', company: 'Elsewhere')],
          [_warehouse(_wip, 'WH-WIP1', disabled: true)],
          [_warehouse(_wip, 'WH-WIP1', group: true)],
        ]) {
          expect(
            warehouseFromRackPrefix(
              rack: _rack,
              company: _company,
              abbreviation: 'KA',
              warehouses: warehouses,
            ),
            isNull,
          );
        }
        expect(
          warehouseFromRackPrefix(
            rack: 'KA-WH-WIP1-  ',
            company: _company,
            abbreviation: 'KA',
            warehouses: [_warehouse(_wip, 'WH-WIP1')],
          ),
          isNull,
        );
      },
    );
  });

  group('Document divergence', () {
    test('distinct peers with a blank header', () {
      final difference = WarehouseDivergence(
        side: RackSide.source,
        warehouse: _wip,
        header: '',
        peers: [_dxb, _dxb, _wip, null, ' '],
      );
      expect(difference.messages, [
        'This row’s source warehouse is WH-WIP1 - KA. Other rows use WH-DXB1 - KA.',
      ]);
      expect(
        difference.key,
        WarehouseDivergence(
          side: RackSide.source,
          warehouse: _wip,
          peers: [' ', _wip, _dxb],
        ).key,
      );
    });

    test('header, peers and linked Sales Order line are independent baselines', () {
      final difference = WarehouseDivergence(
        side: RackSide.outbound,
        warehouse: _dxb,
        header: _wip,
        peers: [_wip],
        soWarehouse: 'WH-DXB3 - KA',
        soLine: '2',
      );
      expect(difference.messages, [
        'This row’s warehouse is WH-DXB1 - KA. The document default is WH-WIP1 - KA.',
        'This row’s warehouse is WH-DXB1 - KA. Other rows use WH-WIP1 - KA.',
        'This row’s warehouse is WH-DXB1 - KA. Sales Order line 2 uses WH-DXB3 - KA.',
      ]);
    });
  });

  test(
    'legacy baseline permits reduction but rejects other movement or Submit',
    () {
      RackRowSnapshot row(
        double quantity, {
        String item = '2003050',
        String batch = '20030506-4BC87Z',
        String warehouse = _dxb,
        String rack = _rack,
        bool applies = true,
      }) => RackRowSnapshot(
        item: item,
        batch: batch,
        warehouse: warehouse,
        rack: rack,
        applies: applies,
        quantity: quantity,
      );

      final saved = row(2);
      expect(saved.canRetain(row(2)), isTrue);
      expect(saved.canRetain(row(1)), isTrue);
      expect(saved.canRetain(row(3)), isFalse);
    expect(saved.canRetain(row(-1)), isFalse);
      expect(saved.canRetain(row(1, item: 'other')), isFalse);
      expect(saved.canRetain(row(1, batch: 'other')), isFalse);
      expect(saved.canRetain(row(1, warehouse: _wip)), isFalse);
      expect(saved.canRetain(row(1, rack: 'other')), isFalse);
      expect(saved.canRetain(row(1, applies: false)), isFalse);
      expect(saved.canRetain(row(1), submitting: true), isFalse);
    },
  );
}
