import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/global_search_item.dart';
import 'package:multimax/app/modules/global_widgets/global_search_delegate.dart';

/// API-mode search must hit the network once per *settled* query, not once per
/// keystroke — the delegate is rebuilt on every character (and on incidental
/// rebuilds), so an undebounced FutureBuilder fires a request each time.
void main() {
  testWidgets('API mode debounces: typing fires one query, rebuilds fire none',
      (tester) async {
    final queries = <String>[];
    final delegate = DocTypeSearchDelegate(
      doctype: 'Sales Order',
      targetRoute: '/sales-order-form',
      searcher: (doctype, query) async {
        queries.add(query);
        return const <GlobalSearchItem>[];
      },
    );

    Future<void> pumpWith(String q) async {
      delegate.query = q;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: delegate.buildSuggestions),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Type "sal" → "sale" → "sales" faster than the debounce window.
    await pumpWith('sal');
    await pumpWith('sale');
    await pumpWith('sales');
    expect(queries, isEmpty, reason: 'no request while still typing');

    await tester.pump(const Duration(milliseconds: 350));
    expect(queries, ['sales'], reason: 'one request for the settled query');

    // An incidental rebuild at an unchanged query must reuse the cached future.
    await pumpWith('sales');
    await tester.pump(const Duration(milliseconds: 350));
    expect(queries, ['sales'], reason: 'rebuild must not re-fire the network');

    await tester.pumpAndSettle();
  });
}
