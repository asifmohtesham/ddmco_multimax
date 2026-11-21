// test/unit/item_variant_details_logic_test.dart
//
// Row shapes are the ones the live server returned on ERPNext v16.55.0
// (15/11/2026) and the ones v15 returns.
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/stock/reports/item_variant_details/item_variant_details_logic.dart';

void main() {
  test('footer sums variant quantities once and keeps stock UOMs separate', () {
    final totals = variantQuantitySummary(
      [
        {'indent': 0, 'current_stock': 72, 'stock_uom': 'Nos'},
        {
          'indent': 1,
          'current_stock': 72.0,
          'in_production': 0,
          'stock_uom': 'Nos',
          'open_orders': 4,
          'avg_selling_price_list_rate': 2.92,
        },
        {'indent': 1, 'current_stock': 0, 'stock_uom': 'Nos'},
        {'indent': 1, 'current_stock': 1.5, 'stock_uom': 'Kg'},
      ],
      [
        {'fieldname': 'current_stock', 'label': 'Current Stock'},
        {'fieldname': 'in_production', 'label': 'In Production'},
      ],
    );
    expect(totals, [
      'Current Stock 72 Nos',
      'In Production 0 Nos',
      'Current Stock 1.5 Kg',
    ]);
  });

  // v16.55: template subtotal row, then its variants.
  final v16Template = <String, dynamic>{
    'variant_name': '---WAL',
    'item_group': 'Wallets',
    'indent': 0,
    'open_orders': 1,
    'stock_uom': 'Nos',
    'current_stock': 12.0,
    'in_production': 0,
  };
  final v16Variant = <String, dynamic>{
    'variant_name': '1001439',
    'template': '---WAL',
    'item_group': 'Wallets',
    'indent': 1,
    'colour': 'MIX',
    'stock_uom': 'Nos',
    'current_stock': 12.0,
    'in_production': 0,
    'open_orders': 1,
  };
  // v15: no template row, and no `indent` on any row.
  final v15Variant = <String, dynamic>{
    'variant_name': '1001439',
    'colour': 'MIX',
    'current_stock': 12.0,
    'in_production': 0,
    'open_orders': 1,
  };

  group('isTemplateRow', () {
    test('v16.55 template subtotal row', () {
      expect(isTemplateRow(v16Template), isTrue);
    });

    test('v16.55 variant row', () {
      expect(isTemplateRow(v16Variant), isFalse);
    });

    test('v15 variant row (no indent) is never a template', () {
      expect(isTemplateRow(v15Variant), isFalse);
    });

    test('indent sent as 0.0 still marks a template; other values do not', () {
      expect(isTemplateRow({...v16Template, 'indent': 0.0}), isTrue);
      expect(isTemplateRow({...v16Template, 'indent': null}), isFalse);
      expect(isTemplateRow({...v16Template, 'indent': '0'}), isFalse);
      expect(isTemplateRow({...v16Template, 'indent': 2}), isFalse);
    });

    test('variantRowsOf drops the template rows only', () {
      expect(variantRowsOf([v16Template, v16Variant]), [v16Variant]);
      expect(variantRowsOf([v15Variant, v15Variant]), hasLength(2));
    });
  });

  group('templateTotals', () {
    const columns = [
      {'fieldname': 'variant_name', 'label': 'Variant'},
      {'fieldname': 'current_stock', 'label': 'Current Stock'},
      {'fieldname': 'in_production', 'label': 'In Production'},
      {'fieldname': 'open_orders', 'label': 'Open Sales Orders'},
    ];

    test('uses the report\'s own column labels, in report order', () {
      expect(templateTotals(v16Template, columns), [
        (label: 'Current Stock', value: '12 Nos'),
        (label: 'In Production', value: '0 Nos'),
        (label: 'Open Sales Orders', value: '1'),
      ]);
    });

    test('omits figures the server left empty (mixed stock UOMs)', () {
      final mixed = {
        ...v16Template,
        'current_stock': null,
        'in_production': '',
      };
      expect(templateTotals(mixed, columns), [
        (label: 'Open Sales Orders', value: '1'),
      ]);
    });

    test('falls back to the fieldname when a column has no label', () {
      expect(templateTotals({'open_orders': 2}, const []), [
        (label: 'open_orders', value: '2'),
      ]);
    });
  });

  test('formatReportNumber drops a trailing .0 only', () {
    expect(formatReportNumber(12.0), '12');
    expect(formatReportNumber(1.5), '1.5');
    expect(formatReportNumber(3), '3');
    expect(formatReportNumber(null), '');
  });

  group('loaded results', () {
    final columns = <VariantRow>[
      {'fieldname': 'colour'},
    ];

    test(
      'grouped search finds codes, fetched names and populated attributes',
      () {
        final data = VariantResults([
          v16Template,
          v16Variant,
          {
            'variant_name': '1001440',
            'indent': 1,
            'colour': '-',
            'current_stock': 0,
          },
          {'variant_name': 'EMPTY', 'indent': 0},
        ], columns);
        expect(data.templateCount, 2);
        expect(data.variants, hasLength(2));
        expect(data.filter(query: 'mIx').single.variants, [v16Variant]);
        expect(data.filter(query: '1001439').single.group.code, '---WAL');
        expect(
          data
              .filter(
                query: ' wallet ',
                details: {
                  '1001439': {'item_name': 'Travel Wallet'},
                },
              )
              .single
              .variants,
          [v16Variant],
        );
        expect(data.filter(query: 'wal').single.variants, hasLength(2));
        expect(data.filter(query: 'EMPTY').single.variants, isEmpty);
        expect(data.filter(query: 'EMPTY', inStock: true), isEmpty);
      },
    );

    test('legacy flat search and stock use only matching quantity totals', () {
      final data = VariantResults([
        v15Variant,
        {
          'item': 'Z',
          'variant_of': 'OLD',
          'current_stock': -4,
          'in_production': 9,
        },
      ], columns);
      expect(data.templateCount, 0);
      final singleTemplate = VariantResults(
        [v15Variant],
        columns,
        singleRequestedTemplate: 'Legacy template',
      );
      expect(singleTemplate.filter(query: 'legacy').single.variants, [
        v15Variant,
      ]);
      expect(data.filter(query: 'old').single.variants.single['item'], 'Z');
      expect(data.filter(query: 'MIX').single.variants, [v15Variant]);
      final shown = data.filter(inStock: true).single.variants;
      expect(shown, [v15Variant]);
      expect(variantQuantitySummary(shown, columns), [
        'Current Stock 12',
        'In Production 0',
      ]);
    });

    test('collapse threshold is 200 variants and overrides restore', () {
      VariantResults data(int count) => VariantResults([
        v16Template,
        for (var i = 0; i < count; i++) {...v16Variant},
      ], columns);
      final small = data(200);
      expect(small.isExpanded(small.groups.single), isTrue);
      final large = data(201);
      final group = large.groups.single;
      expect(large.isExpanded(group), isFalse);
      large.toggle(group);
      expect(large.isExpanded(group), isTrue);
      final saved = large.expansion;
      large.setAllExpanded(false);
      expect(large.isExpanded(group), isFalse);
      large.restoreExpansion(saved);
      expect(large.isExpanded(group), isTrue);
    });
  });
}
