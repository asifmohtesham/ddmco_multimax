import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/todo_model.dart';
import 'package:multimax/app/modules/home/widgets/dashboard_todo_card.dart';

ToDo _todo({
  String name = 'TD-0001',
  String status = 'Open',
  String description = 'Do the thing',
  String priority = 'Medium',
  String date = '',
}) {
  return ToDo(
    name: name,
    status: status,
    description: description,
    modified: '2026-07-11 09:00:00',
    priority: priority,
    date: date,
  );
}

void main() {
  group('todoPlainText', () {
    test('strips tags and collapses whitespace', () {
      expect(
        todoPlainText('<div class="ql-editor"><p>Pack <b>DN-101</b></p>\n<p>today</p></div>'),
        'Pack DN-101 today',
      );
    });

    test('turns <br> into a space and decodes common entities', () {
      expect(
        todoPlainText('Check&nbsp;racks<br/>A &amp; B &lt;urgent&gt;'),
        'Check racks A & B <urgent>',
      );
    });

    test('plain text passes through unchanged', () {
      expect(todoPlainText('Call supplier'), 'Call supplier');
    });

    test('empty input stays empty', () {
      expect(todoPlainText(''), '');
    });
  });

  group('selectUpcomingTodos', () {
    test('orders dated todos ascending and puts dateless last', () {
      final todos = [
        _todo(name: 'no-date-1'),
        _todo(name: 'late', date: '2026-08-01'),
        _todo(name: 'soon', date: '2026-07-12'),
        _todo(name: 'no-date-2'),
      ];
      final result = selectUpcomingTodos(todos);
      expect(result.map((t) => t.name).toList(),
          ['soon', 'late', 'no-date-1', 'no-date-2']);
    });

    test('caps the result at max', () {
      final todos = List.generate(
          8, (i) => _todo(name: 'td-$i', date: '2026-07-1${i + 1}'));
      expect(selectUpcomingTodos(todos, max: 5).length, 5);
    });

    test('dated todos are never crowded out by dateless ones', () {
      final todos = [
        for (var i = 0; i < 5; i++) _todo(name: 'dateless-$i'),
        _todo(name: 'dated', date: '2026-07-20'),
      ];
      final result = selectUpcomingTodos(todos, max: 5);
      expect(result.first.name, 'dated');
      expect(result.length, 5);
    });
  });

  group('dueLabelFor', () {
    final today = DateTime(2026, 7, 11);

    test('returns null for empty or unparseable dates', () {
      expect(dueLabelFor('', today), isNull);
      expect(dueLabelFor('not-a-date', today), isNull);
    });

    test('past date is overdue', () {
      final label = dueLabelFor('2026-07-03', today)!;
      expect(label.isOverdue, isTrue);
      expect(label.text, contains('Overdue'));
      expect(label.text, contains('3 Jul'));
    });

    test('same day is "Due today", not overdue', () {
      final label = dueLabelFor('2026-07-11', today)!;
      expect(label.isOverdue, isFalse);
      expect(label.text, 'Due today');
    });

    test('future date shows the day', () {
      final label = dueLabelFor('2026-07-15', today)!;
      expect(label.isOverdue, isFalse);
      expect(label.text, 'Due 15 Jul');
    });
  });

  group('DashboardTodoCard', () {
    Future<void> pump(WidgetTester tester, ToDo todo,
        {Brightness brightness = Brightness.light,
        VoidCallback? onTap}) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: DashboardTodoCard(todo: todo, onTap: onTap ?? () {}),
        ),
      ));
    }

    testWidgets('renders stripped description and priority', (tester) async {
      await pump(
        tester,
        _todo(
          description: '<p>Pack <b>DN-101</b></p>',
          priority: 'High',
          date: '2026-09-01',
        ),
      );
      expect(find.text('Pack DN-101'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.textContaining('Due'), findsOneWidget);
    });

    testWidgets('falls back to the ToDo name when description is empty',
        (tester) async {
      await pump(tester, _todo(description: '', name: 'TD-0042'));
      expect(find.text('TD-0042'), findsOneWidget);
    });

    testWidgets('fires onTap', (tester) async {
      var tapped = false;
      await pump(tester, _todo(), onTap: () => tapped = true);
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('renders in dark mode', (tester) async {
      await pump(
        tester,
        _todo(priority: 'Urgent', date: '2020-01-01'),
        brightness: Brightness.dark,
      );
      expect(find.textContaining('Overdue'), findsOneWidget);
    });
  });
}
