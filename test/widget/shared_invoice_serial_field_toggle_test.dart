import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/shared/item_sheet/serial_field_mixin.dart';
import 'package:multimax/app/shared/item_sheet/serial_number_field_delegate.dart';
import 'package:multimax/app/shared/item_sheet/widgets/shared_invoice_serial_number_field.dart';

class _FakeSerialController extends GetxController with SerialFieldMixin {
  _FakeSerialController({this.supportsToggle = true});

  final bool supportsToggle;

  @override
  bool get supportsAllowFullToggle => supportsToggle;

  @override
  List<String> get availableSerialNos => ['1', '2'];

  @override
  double posItemQtyForSerial(String serial) => 10.0;

  @override
  SerialDropdownItem? posDropdownItemFor(String serial) => SerialDropdownItem(
        serial: serial,
        itemName: 'Item $serial',
        qty: 10.0,
        remaining: serial == '1' ? 0.0 : 10.0, // serial 1 is Full
        used: serial == '1' ? 10.0 : 0.0,
      );
}

Widget _host(SerialNumberFieldDelegate c) => MaterialApp(
      home: Scaffold(
        body: SharedInvoiceSerialNumberField(c: c),
      ),
    );

void main() {
  testWidgets('Allow Full toggle shown for default adopters with a Full row',
      (tester) async {
    final c = _FakeSerialController(supportsToggle: true);
    await tester.pumpWidget(_host(c));
    expect(find.text('Allow Full'), findsOneWidget);
  });

  testWidgets('Allow Full toggle hidden when supportsAllowFullToggle is false',
      (tester) async {
    final c = _FakeSerialController(supportsToggle: false);
    await tester.pumpWidget(_host(c));
    expect(find.text('Allow Full'), findsNothing);
  });
}
