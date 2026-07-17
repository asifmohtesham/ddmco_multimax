import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_actionable_preview.dart';

Future<void> _pump(WidgetTester t, Widget child,
        {Brightness b = Brightness.light}) =>
    t.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(body: child),
    ));

String _owner(String e) => ownerLabelFor(e, const {'jawwad@x.com': 'Jawwad Ahmed'});

void main() {
  group('ownerLabelFor', () {
    test('known user resolves to the display name', () {
      expect(ownerLabelFor('jawwad@x.com', const {'jawwad@x.com': 'Jawwad Ahmed'}),
          'Jawwad Ahmed');
    });

    test('unknown user falls back to the email local part', () {
      expect(ownerLabelFor('someone@x.com', const {}), 'someone');
    });

    test('empty email yields empty label', () {
      expect(ownerLabelFor('', const {}), '');
    });

    test('malformed email (no @) returns as-is', () {
      expect(ownerLabelFor('administrator', const {}), 'administrator');
    });
  });

  group('docRowFor', () {
    test('Purchase Order: supplier, owner, transaction_date', () {
      final r = docRowFor('Purchase Order', {
        'name': 'PO-0421',
        'supplier': 'Acme Corp',
        'transaction_date': '2026-07-12',
        'owner': 'jawwad@x.com',
      }, _owner);
      expect(r.name, 'PO-0421');
      expect(r.subtitle, 'Acme Corp · Jawwad Ahmed · 12 Jul');
    });

    test('Delivery Note uses customer + posting_date', () {
      final r = docRowFor('Delivery Note', {
        'name': 'DN-0198',
        'customer': 'Zenith Ltd',
        'posting_date': '2026-07-11',
        'owner': 'unknown@x.com',
      }, _owner);
      expect(r.subtitle, 'Zenith Ltd · unknown · 11 Jul');
    });

    test('Stock Entry uses stock_entry_type', () {
      final r = docRowFor('Stock Entry', {
        'name': 'SE-0031',
        'stock_entry_type': 'Material Issue',
        'posting_date': '2026-07-10',
        'owner': 'jawwad@x.com',
      }, _owner);
      expect(r.subtitle, 'Material Issue · Jawwad Ahmed · 10 Jul');
    });

    test('Packing Slip uses delivery_note and falls back to creation', () {
      final r = docRowFor('Packing Slip', {
        'name': 'PS-0009',
        'delivery_note': 'DN-0198',
        'creation': '2026-07-09 08:30:00',
        'owner': 'jawwad@x.com',
      }, _owner);
      expect(r.subtitle, 'DN-0198 · Jawwad Ahmed · 9 Jul');
    });

    test('empty segments are omitted — no stray separators', () {
      final r = docRowFor('Purchase Receipt', {
        'name': 'PR-0087',
        'supplier': '',
        'posting_date': '',
        'owner': '',
      }, _owner);
      expect(r.name, 'PR-0087');
      expect(r.subtitle, '');
    });

    test('unparseable date is dropped rather than rendered raw', () {
      final r = docRowFor('Purchase Order', {
        'name': 'PO-1',
        'supplier': 'Acme',
        'transaction_date': 'not-a-date',
        'owner': '',
      }, _owner);
      expect(r.subtitle, 'Acme');
    });
  });

  group('ActionableDocPreview', () {
    testWidgets('renders a row per entry plus View All', (t) async {
      await _pump(t, ActionableDocPreview(
        isLoading: false,
        onViewAll: () {},
        rows: const [
          ActionableDocRowData(name: 'PO-1', subtitle: 'Acme · Jawwad · 12 Jul'),
          ActionableDocRowData(name: 'PO-2', subtitle: 'Bolt · Jawwad · 11 Jul'),
          ActionableDocRowData(name: 'PO-3', subtitle: 'Zen · Jawwad · 10 Jul'),
        ],
      ));
      expect(find.byType(ActionableDocRow), findsNWidgets(3));
      expect(find.text('View All'), findsOneWidget);
      expect(find.text('PO-1'), findsOneWidget);
      expect(find.text('Acme · Jawwad · 12 Jul'), findsOneWidget);
    });

    testWidgets('View All fires', (t) async {
      var tapped = false;
      await _pump(t, ActionableDocPreview(
        isLoading: false,
        onViewAll: () => tapped = true,
        rows: const [ActionableDocRowData(name: 'PO-1', subtitle: 's')],
      ));
      await t.tap(find.text('View All'));
      expect(tapped, isTrue);
    });

    testWidgets('row tap fires', (t) async {
      var tapped = false;
      await _pump(t, ActionableDocPreview(
        isLoading: false,
        onViewAll: () {},
        rows: [ActionableDocRowData(name: 'PO-1', subtitle: 's', onTap: () => tapped = true)],
      ));
      await t.tap(find.byType(ActionableDocRow));
      expect(tapped, isTrue);
    });

    testWidgets('isLoading shows a skeleton, not rows', (t) async {
      await _pump(t, ActionableDocPreview(
          isLoading: true, rows: const [], onViewAll: () {}));
      expect(find.byType(ActionableDocRow), findsNothing);
      expect(find.byKey(const ValueKey('actionable-preview-loading')), findsOneWidget);
    });

    testWidgets('empty and not loading collapses', (t) async {
      await _pump(t, ActionableDocPreview(
          isLoading: false, rows: const [], onViewAll: () {}));
      expect(find.byType(ActionableDocRow), findsNothing);
      expect(find.text('View All'), findsNothing);
    });

    testWidgets('renders in dark mode', (t) async {
      await _pump(t, ActionableDocPreview(
        isLoading: false,
        onViewAll: () {},
        rows: const [ActionableDocRowData(name: 'PO-1', subtitle: 'Acme · 12 Jul')],
      ), b: Brightness.dark);
      expect(find.text('PO-1'), findsOneWidget);
    });
  });
}
