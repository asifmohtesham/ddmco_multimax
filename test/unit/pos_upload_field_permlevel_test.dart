import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// A `frappe.desk.form.load.getdoctype` payload mirroring the live POS
/// Upload DocType: the `status` field sits at permlevel 1, and only some
/// roles hold a level-1 write rule.
Map<String, dynamic> _posUploadMeta({int statusPermlevel = 1}) => {
      'docs': [
        {
          'doctype': 'DocType',
          'name': 'POS Upload',
          'fields': [
            {'fieldname': 'date', 'permlevel': 0},
            {'fieldname': 'customer'}, // permlevel omitted → level 0
            {'fieldname': 'status', 'permlevel': statusPermlevel},
          ],
          'permissions': [
            // Level 0 — document access.
            {'role': 'System Manager', 'read': 1, 'write': 1, 'permlevel': 0},
            {'role': 'Sales Manager', 'read': 1, 'write': 1, 'permlevel': 0},
            {'role': 'Sales User', 'read': 1, 'write': 1}, // permlevel omitted
            {
              'role': 'Stock User - Custom',
              'read': 1,
              'write': 1,
              'permlevel': 0
            },
            // Level 1 — the status field gate.
            {'role': 'System Manager', 'read': 1, 'write': 1, 'permlevel': 1},
            {'role': 'Sales Manager', 'read': 1, 'write': 1, 'permlevel': 1},
            {'role': 'Sales User', 'read': 1, 'write': 0, 'permlevel': 1},
            {
              'role': 'Stock User - Custom',
              'read': 1,
              'write': 1,
              'permlevel': 1
            },
          ],
        },
        {
          'doctype': 'DocType',
          'name': 'POS Upload Item',
          'fields': [
            {'fieldname': 'status', 'permlevel': 0}, // must not shadow parent
          ],
          'permissions': [
            {'role': 'Ghost Role', 'write': 1, 'permlevel': 1},
          ],
        },
      ],
      'user_settings': const {},
    };

void main() {
  group('ApiProvider.fieldPermlevel', () {
    test('reads the status field permlevel from the parent doctype', () {
      expect(
          ApiProvider.fieldPermlevel(_posUploadMeta(), 'POS Upload', 'status'),
          1);
    });

    test('field without an explicit permlevel is level 0', () {
      expect(
          ApiProvider.fieldPermlevel(
              _posUploadMeta(), 'POS Upload', 'customer'),
          0);
    });

    test('missing field or unparseable meta yields null', () {
      expect(
          ApiProvider.fieldPermlevel(_posUploadMeta(), 'POS Upload', 'nope'),
          isNull);
      expect(ApiProvider.fieldPermlevel(null, 'POS Upload', 'status'), isNull);
      expect(ApiProvider.fieldPermlevel({'docs': 'junk'}, 'POS Upload', 'status'),
          isNull);
    });
  });

  group('ApiProvider.rolesWithPermission at permlevel 1', () {
    test('returns only roles with a level-1 write rule', () {
      final writers = ApiProvider.rolesWithPermission(
          _posUploadMeta(), 'POS Upload', 'write',
          permlevel: 1);
      expect(writers,
          {'System Manager', 'Sales Manager', 'Stock User - Custom'});
      expect(writers, isNot(contains('Sales User')));
      expect(writers, isNot(contains('Ghost Role')));
    });

    test('permlevel 0 extraction is unchanged (omitted permlevel counts)', () {
      final writers =
          ApiProvider.rolesWithPermission(_posUploadMeta(), 'POS Upload', 'write');
      expect(writers, contains('Sales User'));
    });
  });

  group('ApiProvider.fieldWriteGranted', () {
    test('Sales User (Samaan) cannot write the permlevel-1 status field', () {
      expect(
          ApiProvider.fieldWriteGranted(_posUploadMeta(), 'POS Upload',
              'status', {'Employee', 'Sales User'}),
          isFalse);
    });

    test('roles with a level-1 write rule pass', () {
      expect(
          ApiProvider.fieldWriteGranted(_posUploadMeta(), 'POS Upload',
              'status', {'Stock User - Custom'}),
          isTrue);
      expect(
          ApiProvider.fieldWriteGranted(
              _posUploadMeta(), 'POS Upload', 'status', {'Sales Manager'}),
          isTrue);
    });

    test('System Manager bypasses, mirroring the app-wide role convention',
        () {
      expect(
          ApiProvider.fieldWriteGranted(
              _posUploadMeta(), 'POS Upload', 'status', {'System Manager'}),
          isTrue);
    });

    test('a permlevel-0 status field is governed by doc-level write alone',
        () {
      expect(
          ApiProvider.fieldWriteGranted(_posUploadMeta(statusPermlevel: 0),
              'POS Upload', 'status', {'Sales User'}),
          isTrue);
    });

    test('fails closed on unparseable meta or unknown field', () {
      expect(
          ApiProvider.fieldWriteGranted(
              null, 'POS Upload', 'status', {'System Manager'}),
          isFalse);
      expect(
          ApiProvider.fieldWriteGranted(
              _posUploadMeta(), 'POS Upload', 'missing', {'System Manager'}),
          isFalse);
    });

    test('empty role set is denied for a gated field', () {
      expect(
          ApiProvider.fieldWriteGranted(
              _posUploadMeta(), 'POS Upload', 'status', const {}),
          isFalse);
    });
  });
}
