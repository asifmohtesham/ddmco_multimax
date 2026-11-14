import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/doc_card_skeleton.dart';
import 'package:multimax/app/modules/global_widgets/skeleton_box.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(brightness: Brightness.light),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('DocCardSkeleton renders several SkeletonBoxes', (tester) async {
    await tester.pumpWidget(_host(const DocCardSkeleton()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SkeletonBox), findsAtLeastNWidgets(3));
  });

  testWidgets('DocCardSkeletonList renders the requested count', (tester) async {
    await tester.pumpWidget(_host(
      const SingleChildScrollView(child: DocCardSkeletonList(count: 4)),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(DocCardSkeleton), findsNWidgets(4));
  });

  testWidgets('DocCardSkeletonList defaults to 5', (tester) async {
    await tester.pumpWidget(_host(
      const SingleChildScrollView(child: DocCardSkeletonList()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(DocCardSkeleton), findsNWidgets(5));
  });
}
