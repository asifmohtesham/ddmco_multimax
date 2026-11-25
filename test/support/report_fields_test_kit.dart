// Keep the shared Material API until the app migrates to material_ui.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/services/database_service.dart';
import 'package:multimax/app/data/services/storage_service.dart';
import 'package:multimax/app/modules/global_widgets/doctype_list_header.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_field.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_anchor.dart';
import 'package:multimax/app/modules/global_widgets/report_fields/report_fields_store.dart';

typedef ExpectedField = ({
  String key,
  String section,
  String column,
  String label,
  bool defaultVisible,
  bool locked,
});

abstract interface class ReportFieldsFixture {
  List<ExpectedField> get expectedFields;
  int get reportRequests;
  Future<void> mount(
    WidgetTester t, {
    required String site,
    required String user,
  });
  Future<void> reopenWithFreshStore(WidgetTester t);
  Future<List<Object>> readAllOccurrenceIdsInOrder(WidgetTester t);
  Future<void> expectDefaultCards(WidgetTester t);
  Future<void> expectProtectedContentAndTotals(WidgetTester t);
  Future<void> expectOccurrenceDetail(WidgetTester t, String key, bool shown);
  Future<void> showSuccessfulEmpty(WidgetTester t);
  Future<void> showFailure(WidgetTester t);
}

abstract interface class ReportFieldsDriver {
  Future<void> openFields();
  Future<void> setVisible(String key, bool value);
  Future<void> reset();
  Future<void> dismiss();
  Future<void> switchOwner({required String site, required String user});
  Future<void> scrollToOccurrence(Object id);
  double readPaintedOffset(Object id);
  Future<void> scrollToEnd();
}

class ReportFieldsTestOwner implements ReportOwnerSource {
  FieldsOwner? current;
  final _listeners = <void Function()>{};

  void change(String site, String user) {
    current = (scope: (site: site, user: user.trim()), rawUser: user);
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  Future<FieldsOwner?> resolve() async => current;

  @override
  Unsubscribe watch(void Function() onChange) {
    _listeners.add(onChange);
    return () => _listeners.remove(onChange);
  }
}

class ReportFieldsTestConfig extends DatabaseService {
  final values = <String, String>{};
  Future<void> Function(String)? beforeRead;
  Future<void> Function(String, String)? beforeWrite;

  @override
  Future<String?> getConfig(String key) async {
    await beforeRead?.call(key);
    return values[key];
  }

  @override
  Future<void> saveConfig(String key, String value) async {
    await beforeWrite?.call(key, value);
    values[key] = value;
  }
}

class ReportFieldsTestStorage extends StorageService {
  ReportFieldsTestStorage() : super.withStorage(null);

  final legacyValues = <String, Object>{};

  @override
  Object? readLegacyReportFields(String reportId) => legacyValues[reportId];
}

class WidgetReportFieldsDriver implements ReportFieldsDriver {
  WidgetReportFieldsDriver(this.tester, this.owner);

  final WidgetTester tester;
  final ReportFieldsTestOwner owner;

  Finder get _sheet => find
      .ancestor(
        of: find.text('Reset to defaults'),
        matching: find.byType(DraggableScrollableSheet),
      )
      .first;
  Finder get _viewport => find
      .descendant(
        of: find.byType(ReportFieldsResults),
        matching: find.byType(CustomScrollView),
      )
      .first;

  Finder _tile(String key) =>
      find.descendant(of: _sheet, matching: find.byKey(ValueKey(key)));

  Future<CheckboxListTile> read(String key) async {
    final scrollable = find
        .descendant(of: _sheet, matching: find.byType(Scrollable))
        .last;
    if (_tile(key).evaluate().isEmpty) {
      final scroll = tester.state<ScrollableState>(scrollable).position;
      scroll.jumpTo(scroll.minScrollExtent);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(_tile(key), 160, scrollable: scrollable);
    } else {
      await tester.ensureVisible(_tile(key));
    }
    await tester.pumpAndSettle();
    return tester.widget<CheckboxListTile>(_tile(key));
  }

  @override
  Future<void> openFields() async {
    await tester.tap(find.byTooltip('Fields').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Reset to defaults'), findsOneWidget);
  }

  @override
  Future<void> setVisible(String key, bool value) async {
    final tile = await read(key);
    expect(tile.onChanged, isNotNull);
    if (tile.value != value) {
      await tester.tap(_tile(key));
      await tester.pumpAndSettle();
    }
    expect((await read(key)).value, value);
  }

  @override
  Future<void> reset() async {
    await tester.tap(find.text('Reset to defaults'));
    await tester.pumpAndSettle();
    expect(_sheet, findsOneWidget);
  }

  @override
  Future<void> dismiss() async {
    Navigator.of(tester.element(_sheet)).pop();
    await tester.pumpAndSettle();
  }

  @override
  Future<void> switchOwner({required String site, required String user}) async {
    owner.change(site, user);
    await tester.pumpAndSettle();
  }

  ScrollPosition get position =>
      tester.widget<CustomScrollView>(_viewport).controller!.position;

  @override
  Future<void> scrollToOccurrence(Object id) async {
    final row = find.byKey(ValueKey(id));
    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      row,
      210,
      scrollable: find
          .descendant(of: _viewport, matching: find.byType(Scrollable))
          .first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> positionOccurrenceUnderHeader(
    Object id, {
    double offset = -5,
  }) async {
    await scrollToOccurrence(id);
    position.jumpTo(position.pixels + readPaintedOffset(id) - offset);
    await tester.pumpAndSettle();
    expect(readPaintedOffset(id), closeTo(offset, 1));
  }

  @override
  double readPaintedOffset(Object id) =>
      tester.getTopLeft(find.byKey(ValueKey(id))).dy -
      tester.getTopLeft(_viewport).dy -
      (tester
              .renderObject<RenderSliver>(
                find
                    .descendant(
                      of: _viewport,
                      matching: find.byType(DocTypeListHeader),
                    )
                    .first,
              )
              .geometry
              ?.paintExtent ??
          0);

  @override
  Future<void> scrollToEnd() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      if (position.extentAfter < 1) return;
    }
    fail('The results did not reach their end');
  }
}
