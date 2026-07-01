import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

/// A minimal `frappe.desk.form.load.getdoctype` payload (unwrapped `docs`),
/// mirroring the live shape observed for Material Request / Packing Slip.
Map<String, dynamic> _getdoctype(
  String doctype,
  List<Map<String, dynamic>> perms, {
  bool wrapInMessage = false,
}) {
  final body = {
    'docs': [
      {
        'doctype': 'DocType',
        'name': doctype,
        'permissions': perms,
      },
      // An unrelated linked doctype that must be ignored.
      {
        'doctype': 'DocType',
        'name': '$doctype Item',
        'permissions': [
          {'role': 'Ghost Role', 'create': 1, 'write': 1, 'permlevel': 0},
        ],
      },
    ],
    'user_settings': const {},
  };
  return wrapInMessage ? {'message': body} : body;
}

void main() {
  group('ApiProvider.rolesWithPermission', () {
    test('extracts create roles at permlevel 0 for the requested doctype', () {
      final data = _getdoctype('Material Request', [
        {'role': 'Stock User', 'create': 1, 'write': 1, 'permlevel': 0},
        {'role': 'Purchase Manager', 'create': 1, 'write': 1, 'permlevel': 0},
        {'role': 'Read Only Role', 'create': 0, 'write': 0, 'permlevel': 0},
      ]);

      final create =
          ApiProvider.rolesWithPermission(data, 'Material Request', 'create');

      expect(create, {'Stock User', 'Purchase Manager'});
      expect(create, isNot(contains('Read Only Role')));
      // The linked "Material Request Item" rows must not leak in.
      expect(create, isNot(contains('Ghost Role')));
    });

    test('write and create sets can differ', () {
      final data = _getdoctype('Packing Slip', [
        {'role': 'Sales User', 'create': 0, 'write': 1, 'permlevel': 0},
        {'role': 'Stock User', 'create': 1, 'write': 1, 'permlevel': 0},
      ]);

      expect(ApiProvider.rolesWithPermission(data, 'Packing Slip', 'create'),
          {'Stock User'});
      expect(ApiProvider.rolesWithPermission(data, 'Packing Slip', 'write'),
          {'Sales User', 'Stock User'});
    });

    test('ignores non-zero permlevel rows', () {
      final data = _getdoctype('Material Request', [
        {'role': 'Amount Approver', 'create': 1, 'write': 1, 'permlevel': 1},
        {'role': 'Stock User', 'create': 1, 'write': 1, 'permlevel': 0},
      ]);

      expect(ApiProvider.rolesWithPermission(data, 'Material Request', 'write'),
          {'Stock User'});
    });

    test('treats a missing permlevel as level 0', () {
      final data = _getdoctype('Material Request', [
        {'role': 'Stock User', 'create': 1, 'write': 1},
      ]);

      expect(ApiProvider.rolesWithPermission(data, 'Material Request', 'create'),
          {'Stock User'});
    });

    test('tolerates a message-wrapped payload', () {
      final data = _getdoctype('Packing Slip', [
        {'role': 'Stock User', 'create': 1, 'write': 1, 'permlevel': 0},
      ], wrapInMessage: true);

      expect(ApiProvider.rolesWithPermission(data, 'Packing Slip', 'create'),
          {'Stock User'});
    });

    test('fails closed to an empty set on malformed input', () {
      expect(ApiProvider.rolesWithPermission(null, 'X', 'create'), isEmpty);
      expect(ApiProvider.rolesWithPermission('nope', 'X', 'create'), isEmpty);
      expect(ApiProvider.rolesWithPermission({'docs': 'bad'}, 'X', 'create'),
          isEmpty);
      expect(
          ApiProvider.rolesWithPermission(
              {'docs': []}, 'Material Request', 'create'),
          isEmpty);
    });

    test('returns empty when the doctype is not present in docs', () {
      final data = _getdoctype('Material Request', [
        {'role': 'Stock User', 'create': 1, 'write': 1, 'permlevel': 0},
      ]);

      expect(
          ApiProvider.rolesWithPermission(data, 'Delivery Note', 'create'),
          isEmpty);
    });
  });
}
