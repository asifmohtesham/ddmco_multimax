import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/models/delivery_note_model.dart';
import 'package:multimax/app/data/models/pos_upload_model.dart';
import 'package:multimax/app/modules/delivery_note/form/so_pick.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/so_pick_header.dart';
import 'package:multimax/app/modules/delivery_note/form/widgets/voucher_assignment_sheet.dart';

PosUploadItem _line(int idx, String name, double qty) => PosUploadItem(
    idx: idx, refCode: '', itemName: name, quantity: qty, rate: 1, amount: qty);

final _rows = [
  DeliveryNoteItem(itemCode: '3000247', itemName: 'BELTS', qty: 3, rate: 5, batchNo: 'B1'),
  DeliveryNoteItem(itemCode: '3000248', itemName: 'BELTS', qty: 2, rate: 60, batchNo: 'B2'),
];

Widget _host(Widget child, Brightness b) => GetMaterialApp(
      theme: ThemeData(brightness: b),
      home: Scaffold(body: child),
    );

Future<void> _choose(WidgetTester t, int row, String option) async {
  await t.tap(find.byKey(Key('voucher_line_$row')));
  await t.pumpAndSettle();
  await t.tap(find.text(option).last);
  await t.pumpAndSettle();
}

void main() {
  for (final b in Brightness.values) {
    group('VoucherAssignmentSheet ($b)', () {
      late Map<int, int>? confirmed;
      late String? reply;

      Future<void> pump(WidgetTester t, List<PosUploadItem> lines) async {
        confirmed = null;
        reply = null;
        t.view.physicalSize = const Size(1080, 2400);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(_host(
          VoucherAssignmentSheet(
            uploadName: 'ML-2026-00001',
            rows: _rows,
            lines: lines,
            busy: false.obs,
            onConfirm: (m) async {
              confirmed = m;
              return reply;
            },
          ),
          b,
        ));
        await t.pumpAndSettle();
      }

      testWidgets('asks for every row before linking', (t) async {
        await pump(t, [_line(1, 'BELTS CASUAL', 5), _line(2, 'BELTS FORMAL', 2)]);
        expect(find.text('Assign 2 more'), findsOneWidget);
        await t.tap(find.text('Assign 2 more'));
        await t.pumpAndSettle();
        expect(find.text('Assign every row to a voucher line.'), findsOneWidget);
        expect(confirmed, isNull);
      });

      testWidgets('two rows may share one voucher line up to its qty',
          (t) async {
        await pump(t, [_line(1, 'BELTS CASUAL', 5), _line(2, 'BELTS FORMAL', 2)]);
        await _choose(t, 0, '#1 · BELTS CASUAL (5)');
        await _choose(t, 1, '#1 · BELTS CASUAL (5)');
        expect(find.text('#1 · 5/5'), findsOneWidget);
        await t.tap(find.text('Link & save'));
        await t.pumpAndSettle();
        expect(confirmed, {0: 1, 1: 1});
      });

      testWidgets('flags an over-filled line live', (t) async {
        await pump(t, [_line(1, 'BELTS CASUAL', 4), _line(2, 'BELTS FORMAL', 2)]);
        await _choose(t, 0, '#1 · BELTS CASUAL (4)');
        await _choose(t, 1, '#1 · BELTS CASUAL (4)');
        expect(find.text('Over-filled: #1 by 1'), findsOneWidget);
      });

      testWidgets('shows the server-side error and stays open', (t) async {
        await pump(t, [_line(1, 'BELTS CASUAL', 5)]);
        reply = 'Voucher line over-filled: #1 by 1. Reduce or reassign rows.';
        await _choose(t, 0, '#1 · BELTS CASUAL (5)');
        await _choose(t, 1, '#1 · BELTS CASUAL (5)');
        await t.tap(find.text('Link & save'));
        await t.pumpAndSettle();
        expect(find.textContaining('Reduce or reassign'), findsOneWidget);
        expect(find.text('Assign voucher lines'), findsOneWidget);
      });
    });

    group('SoUploadLinkBanner ($b)', () {
      testWidgets('pending: explains and offers assignment', (t) async {
        var tapped = false;
        await t.pumpWidget(_host(
            SoUploadLinkBanner(
                link: SoUploadLink.pendingAssignment,
                soPoNo: 'ML-2026-00001',
                onAssign: () => tapped = true),
            b));
        expect(find.textContaining('ML-2026-00001 is now linked'), findsOneWidget);
        await t.tap(find.byKey(const Key('assign_voucher_lines')));
        expect(tapped, isTrue);
      });

      testWidgets('none: provisional hint; linked: nothing', (t) async {
        await t.pumpWidget(_host(
            SoUploadLinkBanner(
                link: SoUploadLink.none, soPoNo: null, onAssign: () {}),
            b));
        expect(find.textContaining('provisional'), findsOneWidget);
        await t.pumpWidget(_host(
            SoUploadLinkBanner(
                link: SoUploadLink.linked, soPoNo: 'ML-2026-00001', onAssign: () {}),
            b));
        expect(find.byType(Text), findsNothing);
      });

      testWidgets('wrong family: error', (t) async {
        await t.pumpWidget(_host(
            SoUploadLinkBanner(
                link: SoUploadLink.wrongFamily, soPoNo: 'KX-2026-1', onAssign: () {}),
            b));
        expect(find.textContaining('Stock Entry upload'), findsOneWidget);
      });
    });
  }
}
