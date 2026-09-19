import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/sales_order_model.dart';
import 'package:multimax/app/modules/selling/sales_order/sales_order_logic.dart';

SalesOrder so({
  int docstatus = 1,
  String status = 'To Deliver and Bill',
  double perDelivered = 0,
  double perBilled = 0,
  bool skipDn = false,
  List<SalesOrderItem>? items,
}) =>
    SalesOrder(
      name: 'SAL-ORD-2026-00001',
      customer: 'C1',
      transactionDate: '2026-09-19',
      company: 'Multimax',
      sellingPriceList: 'Standard Selling',
      docstatus: docstatus,
      status: status,
      perDelivered: perDelivered,
      perBilled: perBilled,
      skipDeliveryNote: skipDn,
      items: items ??
          const [SalesOrderItem(name: 'r1', itemCode: 'I1', itemName: 'I1', qty: 5)],
    );

const all = SoPerms(write: true, submit: true, cancel: true, createDn: true);

void main() {
  group('allowedActions', () {
    test('unresolved perms fail closed (empty set) on every state', () {
      const none = SoPerms();
      expect(allowedActions(so(docstatus: 0, status: 'Draft'), none), isEmpty);
      expect(allowedActions(so(), none), isEmpty);
      expect(allowedActions(so(status: 'On Hold'), none), isEmpty);
      expect(allowedActions(so(status: 'Closed'), none), isEmpty);
    });

    test('draft: save needs write, submit needs submit', () {
      final d = so(docstatus: 0, status: 'Draft');
      expect(allowedActions(d, all), {SoAction.save, SoAction.submit});
      expect(allowedActions(d, const SoPerms(write: true, submit: false)),
          {SoAction.save});
    });

    test('open submitted order: hold + close + cancel + makeDn', () {
      expect(allowedActions(so(), all), {
        SoAction.hold, SoAction.close, SoAction.cancel, SoAction.makeDn,
      });
    });

    test('status changes need submit, not write (update_status checks submit)', () {
      final a = allowedActions(
          so(), const SoPerms(write: true, submit: false, cancel: false, createDn: false));
      expect(a, isEmpty);
    });

    test('on hold: resume + close, no hold, no makeDn', () {
      expect(allowedActions(so(status: 'On Hold'), all),
          {SoAction.resume, SoAction.close, SoAction.cancel});
    });

    test('closed: reopen only (+cancel)', () {
      expect(allowedActions(so(status: 'Closed'), all),
          {SoAction.reopen, SoAction.cancel});
    });

    test('fully delivered and billed: no hold/close', () {
      final a = allowedActions(
          so(status: 'Completed', perDelivered: 100, perBilled: 100), all);
      expect(a.intersection({SoAction.hold, SoAction.close}), isEmpty);
    });

    test('cancelled: nothing', () {
      expect(allowedActions(so(docstatus: 2, status: 'Cancelled'), all), isEmpty);
    });
  });

  group('canMakeDeliveryNote', () {
    test('needs an undelivered, non-drop-ship row', () {
      expect(canMakeDeliveryNote(so()), isTrue);
      expect(
          canMakeDeliveryNote(so(items: const [
            SalesOrderItem(itemCode: 'I', itemName: 'I', qty: 5, deliveredQty: 5),
          ])),
          isFalse);
      expect(
          canMakeDeliveryNote(so(items: const [
            SalesOrderItem(itemCode: 'I', itemName: 'I', qty: 5, deliveredBySupplier: true),
          ])),
          isFalse);
    });

    test('blocked by skip_delivery_note, On Hold, Closed, draft', () {
      expect(canMakeDeliveryNote(so(skipDn: true)), isFalse);
      expect(canMakeDeliveryNote(so(status: 'On Hold')), isFalse);
      expect(canMakeDeliveryNote(so(status: 'Closed')), isFalse);
      expect(canMakeDeliveryNote(so(docstatus: 0, status: 'Draft')), isFalse);
    });
  });

  group('buildPayload', () {
    test('editable fields only; no totals, status or VAT columns', () {
      final p = buildPayload(so(docstatus: 0, status: 'Draft', items: const [
        SalesOrderItem(
          name: 'r1', itemCode: 'I1', itemName: 'I1', qty: 2, uom: 'Nos',
          conversionFactor: 1, rate: 10, priceListRate: 12, amount: 20,
          taxAmount: 1, totalAmount: 21, deliveryDate: '2026-09-25',
        ),
      ]));
      expect(p.keys.toSet(), {
        'customer', 'transaction_date', 'order_type', 'company',
        'selling_price_list', 'delivery_date', 'set_warehouse', 'po_no', 'items',
      });
      final row = (p['items'] as List).single as Map;
      expect(row, {
        'name': 'r1', 'item_code': 'I1', 'qty': 2.0, 'uom': 'Nos',
        'conversion_factor': 1.0, 'rate': 10.0,
        'delivery_date': '2026-09-25', 'warehouse': '',
      });
    });

    test('local row ids are stripped; cleared optionals are sent as empty', () {
      final p = buildPayload(so(docstatus: 0, items: const [
        SalesOrderItem(name: 'local_123', itemCode: 'I', itemName: 'I', qty: 1),
      ]));
      expect(((p['items'] as List).single as Map).containsKey('name'), isFalse);
      expect(p['po_no'], '');
      expect(p['set_warehouse'], '');
      expect(p['delivery_date'], '');
    });

    test('empty company / price list are omitted so the server fills them', () {
      final p = buildPayload(const SalesOrder(name: 'x', customer: 'C'));
      expect(p.containsKey('company'), isFalse);
      expect(p.containsKey('selling_price_list'), isFalse);
    });
  });

  group('isSoDirty', () {
    test('equal payloads are clean; an edited qty or header is dirty', () {
      final a = so(docstatus: 0);
      expect(isSoDirty(a, a.copyWith()), isFalse);
      expect(isSoDirty(a, a.copyWith(poNo: 'X')), isTrue);
      expect(
          isSoDirty(a, a.copyWith(items: [a.items.first.copyWith(qty: 9)])),
          isTrue);
    });

    test('server-only fields do not make it dirty', () {
      final a = so(docstatus: 0);
      final b = SalesOrder.fromJson({
        'name': a.name, 'customer': 'C1', 'transaction_date': '2026-09-19',
        'company': 'Multimax', 'selling_price_list': 'Standard Selling',
        'grand_total': 999, 'status': 'Draft',
        'items': [{'name': 'r1', 'item_code': 'I1', 'item_name': 'I1', 'qty': 5, 'tax_amount': 3}],
      });
      expect(isSoDirty(a, b), isFalse);
    });
  });

  group('validateRow', () {
    test('qty > 0 and item required', () {
      expect(
          validateRow(const SalesOrderItem(itemCode: '', itemName: '', qty: 0), '2026-09-19')
              .keys,
          containsAll(['item_code', 'qty']));
    });
    test('delivery date may be blank but not before the order date', () {
      const ok = SalesOrderItem(itemCode: 'I', itemName: 'I', qty: 1);
      expect(validateRow(ok, '2026-09-19'), isEmpty);
      expect(
          validateRow(ok.copyWith(deliveryDate: '2026-09-18'), '2026-09-19')
              .keys,
          ['delivery_date']);
      expect(validateRow(ok.copyWith(deliveryDate: '2026-09-19'), '2026-09-19'),
          isEmpty);
    });
  });

  group('validateOrder', () {
    test('customer and at least one item required', () {
      final e = validateOrder(const SalesOrder(name: 'x', transactionDate: '2026-09-19'));
      expect(e.keys, containsAll(['customer', 'items']));
    });
    test('Sales order needs a delivery date on header or any row', () {
      final noDate = so(docstatus: 0);
      expect(validateOrder(noDate).keys, contains('delivery_date'));
      expect(validateOrder(noDate.copyWith(deliveryDate: '2026-09-30')), isEmpty);
      expect(
          validateOrder(noDate.copyWith(items: [
            noDate.items.first.copyWith(deliveryDate: '2026-09-30'),
          ])),
          isEmpty);
    });
    test('Shopping Cart and skip_delivery_note need no date', () {
      expect(validateOrder(so(docstatus: 0).copyWith(orderType: 'Shopping Cart')),
          isEmpty);
      expect(validateOrder(so(docstatus: 0, skipDn: true)), isEmpty);
    });
    test('header date before order date is rejected', () {
      expect(
          validateOrder(so(docstatus: 0).copyWith(deliveryDate: '2026-09-01')).keys,
          contains('delivery_date'));
    });
  });

  group('parseItemDetails', () {
    test('maps server keys and tolerates missing ones', () {
      final d = parseItemDetails({
        'item_name': 'Widget', 'uom': 'Box', 'stock_uom': 'Nos',
        'conversion_factor': 12, 'price_list_rate': 50, 'rate': 45,
        'warehouse': 'Stores - M',
      });
      expect(d.itemName, 'Widget');
      expect(d.conversionFactor, 12.0);
      expect(d.rate, 45.0);
      expect(d.priceListRate, 50.0);
      final empty = parseItemDetails(null);
      expect(empty.rate, 0.0);
      expect(empty.conversionFactor, 1.0);
    });
  });

  group('statusFilterLabel / progressFraction', () {
    test('string and in-list filters', () {
      expect(statusFilterLabel('Draft'), 'Draft');
      expect(statusFilterLabel(['in', kSoOpenToDeliverStatuses]),
          'Draft, To Deliver and Bill, To Deliver');
    });
    test('progress is clamped to 0..1', () {
      expect(progressFraction(40), 0.4);
      expect(progressFraction(-5), 0.0);
      expect(progressFraction(130), 1.0);
    });
  });

  group('shortDeliveryDate', () {
    test('formats a future date as a plain calendar date, not relative', () {
      expect(shortDeliveryDate('2026-09-24'), '24 Sep');
    });
    test('empty or unparseable input omits the stat', () {
      expect(shortDeliveryDate(null), isNull);
      expect(shortDeliveryDate(''), isNull);
      expect(shortDeliveryDate('not-a-date'), isNull);
    });
  });

  group('parseDeliveryDateFilter', () {
    test('two-sided between yields both bounds', () {
      final r = parseDeliveryDateFilter(
          ['between', ['2026-09-01', '2026-09-30']]);
      expect(r.from, '2026-09-01');
      expect(r.to, '2026-09-30');
    });
    test('one-sided >= yields only from (previously dropped)', () {
      final r = parseDeliveryDateFilter(['>=', '2026-09-01']);
      expect(r.from, '2026-09-01');
      expect(r.to, isNull);
    });
    test('one-sided <= yields only to (previously dropped)', () {
      final r = parseDeliveryDateFilter(['<=', '2026-09-30']);
      expect(r.from, isNull);
      expect(r.to, '2026-09-30');
    });
    test('null or unrecognised shape yields both null', () {
      expect(parseDeliveryDateFilter(null), (from: null, to: null));
      expect(parseDeliveryDateFilter('Draft'), (from: null, to: null));
    });
  });

  group('deriveRowRate', () {
    test('plain price list rate, no margin/discount', () {
      expect(deriveRowRate(const ItemDetails(priceListRate: 15)), 15.0);
    });
    test('percentage margin adds a percentage of the price list rate', () {
      expect(
          deriveRowRate(const ItemDetails(
              priceListRate: 100,
              marginType: 'Percentage',
              marginRateOrAmount: 10)),
          110.0);
    });
    test('amount margin adds a flat amount', () {
      expect(
          deriveRowRate(const ItemDetails(
              priceListRate: 100,
              marginType: 'Amount',
              marginRateOrAmount: 20)),
          120.0);
    });
    test('discount percentage is applied against the margin-adjusted rate', () {
      expect(
          deriveRowRate(
              const ItemDetails(priceListRate: 100, discountPercentage: 10)),
          90.0);
    });
    test('an explicit discount amount takes precedence over the percentage', () {
      expect(
          deriveRowRate(const ItemDetails(
              priceListRate: 100, discountPercentage: 10, discountAmount: 5)),
          95.0);
    });
    test('a non-zero server rate (pricing rule / rate lock) wins outright', () {
      expect(
          deriveRowRate(const ItemDetails(priceListRate: 999, rate: 45)),
          45.0);
    });
    test('everything zero yields zero', () {
      expect(deriveRowRate(const ItemDetails()), 0.0);
    });
  });

  group('resolveDefaultPriceList', () {
    test('party price list wins when non-empty', () {
      expect(
          resolveDefaultPriceList(
              partyPriceList: 'Credit Selling', lastUsed: 'Standard Selling'),
          'Credit Selling');
    });
    test('falls back to last-used when party price list is null or empty', () {
      expect(
          resolveDefaultPriceList(partyPriceList: null, lastUsed: 'Standard Selling'),
          'Standard Selling');
      expect(
          resolveDefaultPriceList(partyPriceList: '', lastUsed: 'Standard Selling'),
          'Standard Selling');
    });
    test('null when neither is set', () {
      expect(resolveDefaultPriceList(partyPriceList: null, lastUsed: null), isNull);
      expect(resolveDefaultPriceList(partyPriceList: '', lastUsed: ''), isNull);
    });
  });

  group('resolveIncomingListFilters', () {
    test('owner equals current email -> mine true, owner stripped, other keys kept', () {
      final r = resolveIncomingListFilters(
          {'owner': 'a@b.com', 'status': 'Draft'}, 'a@b.com');
      expect(r.mine, isTrue);
      expect(r.filters, {'status': 'Draft'});
    });

    test('owner is a different user -> mine false, owner kept', () {
      final r = resolveIncomingListFilters(
          {'owner': 'other@b.com', 'status': 'Draft'}, 'a@b.com');
      expect(r.mine, isFalse);
      expect(r.filters, {'owner': 'other@b.com', 'status': 'Draft'});
    });

    test('no owner -> mine false, filters unchanged', () {
      final r = resolveIncomingListFilters({'status': 'Draft'}, 'a@b.com');
      expect(r.mine, isFalse);
      expect(r.filters, {'status': 'Draft'});
    });

    test('null or empty currentEmail with an owner present -> mine false, owner kept', () {
      final rNull =
          resolveIncomingListFilters({'owner': 'a@b.com'}, null);
      expect(rNull.mine, isFalse);
      expect(rNull.filters, {'owner': 'a@b.com'});

      final rEmpty = resolveIncomingListFilters({'owner': 'a@b.com'}, '');
      expect(rEmpty.mine, isFalse);
      expect(rEmpty.filters, {'owner': 'a@b.com'});
    });

    test('does not mutate the input map', () {
      final incoming = {'owner': 'a@b.com', 'status': 'Draft'};
      resolveIncomingListFilters(incoming, 'a@b.com');
      expect(incoming, {'owner': 'a@b.com', 'status': 'Draft'});
    });
  });
}
