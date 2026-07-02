import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/global_search_targets.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/data/services/global_search_service.dart';
import 'package:multimax/app/modules/global_widgets/global_document_search_delegate.dart';

GlobalSearchTarget _target(String d) => GlobalSearchTarget(
      doctype: d,
      label: '$d s',
      icon: Icons.circle,
      color: Colors.blue,
      route: '/x',
      argsFor: (id) => {'name': id},
    );

void main() {
  testWidgets('renders group headers, rows, and fires onTap', (tester) async {
    final delegate = GlobalDocumentSearchDelegate();
    final groups = [
      GlobalSearchGroup(target: _target('Item'), items: [
        GlobalSearchItem(id: 'FG-1', title: 'Blue Strap', rawData: const {}),
      ]),
      GlobalSearchGroup(target: _target('Delivery Note'), items: [
        GlobalSearchItem(id: 'KA-DN-1', title: 'Acme', rawData: const {}),
      ]),
    ];

    GlobalSearchTarget? tappedTarget;
    GlobalSearchItem? tappedItem;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => delegate.buildResultsList(
            context,
            groups,
            (t, i) {
              tappedTarget = t;
              tappedItem = i;
            },
          ),
        ),
      ),
    ));

    // Section headers
    expect(find.text('ITEM S'), findsOneWidget);
    expect(find.text('DELIVERY NOTE S'), findsOneWidget);
    // Rows
    expect(find.text('Blue Strap'), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);

    await tester.tap(find.text('Blue Strap'));
    expect(tappedTarget?.doctype, 'Item');
    expect(tappedItem?.id, 'FG-1');
  });
}
