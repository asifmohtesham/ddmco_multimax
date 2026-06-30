import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart';

class _FakeBlockedController extends GetxController with SerialFieldMixin {
  @override
  List<String> get availableSerialNos => ['1', '2'];

  @override
  double posItemQtyForSerial(String serial) => 10.0;

  @override
  SerialDropdownItem? posDropdownItemFor(String serial) => SerialDropdownItem(
        serial: serial,
        itemName: 'Item $serial',
        qty: 10.0,
        remaining: 10.0,
        blockedReason: serial == '2' ? 'Strap ≠ Buckle' : null,
      );
}

Widget _host(SerialNumberFieldDelegate c) => MaterialApp(
      home: Scaffold(body: SharedInvoiceSerialNumberField(c: c)),
    );

void main() {
  testWidgets('blocked serial row is disabled and shows the reason', (tester) async {
    final c = _FakeBlockedController();
    await tester.pumpWidget(_host(c));
    // Open the dropdown.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    // The reason text renders for the blocked row.
    expect(find.text('Strap ≠ Buckle'), findsOneWidget);

    // The blocked DropdownMenuItem is disabled.
    final blockedItem = tester.widgetList<DropdownMenuItem<String>>(
      find.byType(DropdownMenuItem<String>),
    ).firstWhere((i) => i.value == '2');
    expect(blockedItem.enabled, isFalse);
  });
}
