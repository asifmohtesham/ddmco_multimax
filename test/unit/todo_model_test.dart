import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/todo_model.dart';

void main() {
  group('ToDo.fromJson', () {
    test('parses a fully-populated Frappe row', () {
      final todo = ToDo.fromJson({
        'name': 'TD-0001',
        'status': 'Closed',
        'description': '<p>Pack DN-101</p>',
        'modified': '2026-07-11 09:00:00',
        'priority': 'High',
        'date': '2026-07-15',
        'reference_type': 'Delivery Note',
        'reference_name': 'DN-00042',
        'allocated_to': 'ops@x.com',
        'owner': 'admin@x.com',
        'assigned_by': 'admin@x.com',
      });

      expect(todo.name, 'TD-0001');
      expect(todo.status, 'Closed');
      expect(todo.description, '<p>Pack DN-101</p>');
      expect(todo.priority, 'High');
      expect(todo.date, '2026-07-15');
      expect(todo.referenceType, 'Delivery Note');
      expect(todo.referenceName, 'DN-00042');
      expect(todo.allocatedTo, 'ops@x.com');
      expect(todo.owner, 'admin@x.com');
      expect(todo.assignedBy, 'admin@x.com');
      expect(todo.hasReference, isTrue);
    });

    test('missing/null fields fall back to documented defaults', () {
      final todo = ToDo.fromJson({'name': 'TD-0002'});

      expect(todo.status, 'Open');
      expect(todo.priority, 'Medium');
      expect(todo.description, '');
      expect(todo.date, '');
      expect(todo.referenceType, '');
      expect(todo.referenceName, '');
      expect(todo.allocatedTo, '');
      expect(todo.owner, '');
      expect(todo.assignedBy, '');
      expect(todo.hasReference, isFalse);
    });

    test('hasReference requires both type and name to be non-empty', () {
      expect(
        ToDo.fromJson({'name': 'TD-1', 'reference_type': 'Delivery Note'})
            .hasReference,
        isFalse,
      );
      expect(
        ToDo.fromJson({'name': 'TD-1', 'reference_name': 'DN-1'}).hasReference,
        isFalse,
      );
    });
  });

  group('ToDo.toJson', () {
    test('round-trips through fromJson', () {
      final original = ToDo.fromJson({
        'name': 'TD-0003',
        'status': 'Open',
        'description': 'Call supplier',
        'modified': '2026-07-11 09:00:00',
        'priority': 'Urgent',
        'date': '2026-07-20',
        'reference_type': 'Purchase Order',
        'reference_name': 'PO-1',
        'allocated_to': 'jane@x.com',
        'owner': 'jane@x.com',
        'assigned_by': '',
      });

      final roundTripped = ToDo.fromJson(original.toJson());

      expect(roundTripped.name, original.name);
      expect(roundTripped.status, original.status);
      expect(roundTripped.description, original.description);
      expect(roundTripped.priority, original.priority);
      expect(roundTripped.date, original.date);
      expect(roundTripped.referenceType, original.referenceType);
      expect(roundTripped.referenceName, original.referenceName);
      expect(roundTripped.allocatedTo, original.allocatedTo);
      expect(roundTripped.owner, original.owner);
    });
  });
}
