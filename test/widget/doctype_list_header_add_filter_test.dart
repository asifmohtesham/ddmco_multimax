import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/add_filter_chip.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/filter_chip_widget.dart';
import 'package:multimax/main.dart';

Widget _host({
  required RxMap activeFilters,
  required RxString searchQuery,
  List<Widget> Function(BuildContext)? chips,
}) {
  return MaterialApp(
    theme: buildAppTheme(AppScheme.light, Brightness.light),
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          DocTypeListHeader(
            title: 'Work Order',
            automaticallyImplyLeading: false,
            activeFilters: activeFilters,
            searchQuery: searchQuery,
            onFilterTap: () {},
            filterChipsBuilder: chips,
            onClearAllFilters: () {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('+ Filter chip shows even when no filter is active',
      (tester) async {
    await tester.pumpWidget(_host(
      activeFilters: <String, dynamic>{}.obs,
      searchQuery: ''.obs,
      chips: (_) => const [],
    ));
    expect(find.byType(AddFilterChip), findsOneWidget);
    expect(find.byType(FilterChipWidget), findsNothing);
  });

  testWidgets('+ Filter chip shows alongside an active filter chip',
      (tester) async {
    await tester.pumpWidget(_host(
      activeFilters: <String, dynamic>{'status': 'Draft'}.obs,
      searchQuery: ''.obs,
      chips: (_) => [
        FilterChipWidget(
            icon: Icons.flag_outlined,
            label: 'Status: Draft',
            onDeleted: () {}),
      ],
    ));
    expect(find.byType(FilterChipWidget), findsOneWidget);
    expect(find.byType(AddFilterChip), findsOneWidget);
  });
}
