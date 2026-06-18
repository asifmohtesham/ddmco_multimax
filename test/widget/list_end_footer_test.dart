import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/list_end_footer.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ListEndFooter', () {
    testWidgets('shows a progress indicator while more pages remain',
        (tester) async {
      await tester.pumpWidget(_wrap(const ListEndFooter(hasMore: true)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('End of results'), findsNothing);
    });

    testWidgets('shows end-of-results label when no more pages',
        (tester) async {
      await tester.pumpWidget(_wrap(const ListEndFooter(hasMore: false)));
      expect(find.text('End of results'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
