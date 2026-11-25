import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/pos_upload/widgets/pos_upload_timeline.dart';

// Builds a timeline for a Delivery-Note-linked (ML/KA) upload with the given
// linked-doc / packing-slip state. Node-1 inputs are held constant.
List<TimelineCheckpoint> _dnTimeline({
  bool isLoadingLinked = false,
  bool hasLinkedDoc = false,
  String linkedDocName = '',
  String linkedDocCreation = '',
  double? orderedQty,
  double? deliveredQty,
  bool isLoadingPackingSlips = false,
  int packingSlipCount = 0,
  String? earliestPackingSlipCreation,
  int packedItems = 0,
  int totalSerials = 0,
  Map<String, dynamic>? deliveryDocInfo,
}) => buildPosUploadTimeline(
  isStockEntryUpload: false,
  posUploadCreation: '2026-06-30 08:00:00',
  itemCount: 20,
  isLoadingLinked: isLoadingLinked,
  hasLinkedDoc: hasLinkedDoc,
  linkedDocName: linkedDocName,
  linkedDocCreation: linkedDocCreation,
  orderedQty: orderedQty,
  deliveredQty: deliveredQty,
  isLoadingPackingSlips: isLoadingPackingSlips,
  packingSlipCount: packingSlipCount,
  earliestPackingSlipCreation: earliestPackingSlipCreation,
  packedItems: packedItems,
  totalSerials: totalSerials,
  deliveryDocInfo: deliveryDocInfo,
);

Map<String, dynamic> _returnVersion({
  required String commentId,
  required String creation,
  required String driverName,
  required String recorderName,
  required String reason,
  String? dn,
}) => {
  'creation': creation,
  'data': jsonEncode({
    'changed': [
      ['status', 'Out for Delivery', 'To Deliver'],
    ],
    'updater_reference': {
      'pos_delivery': {
        'action': 'Delivery Return',
        'driver_name': driverName,
        'recorded_by_name': recorderName,
        'reason': reason,
        'dn': dn,
        'comment_id': commentId,
      },
    },
  }),
};

void main() {
  group('delivery audit history', () {
    test('pairs by comment ID and preserves each return with its own driver', () {
      final firstReturn = _returnVersion(
        commentId: 'return-1',
        creation: '2026-11-25 12:07:00.124200',
        driverName: 'First Driver',
        recorderName: 'First Recorder',
        reason: 'Late',
        dn: 'DN-00001',
      );
      final secondReturn = _returnVersion(
        commentId: 'return-2',
        creation: '2026-11-25 13:18:00.390010',
        driverName: 'Second Driver',
        recorderName: 'Second Recorder',
        reason: 'Rejected',
      );

      final timeline = _dnTimeline(
        deliveryDocInfo: {
          'workflow_logs': [
            {
              'name': 'return-1',
              'content':
                  'POS delivery · Delivery Return · Driver: Summary Driver',
            },
            {'name': 'native-stage', 'content': 'To Deliver'},
            {'name': 'return-2', 'content': 'POS delivery · Delivery Return'},
          ],
          'comments': [
            {'name': 'return-2', 'content': 'POS delivery · Delivery Return'},
          ],
          'versions': [secondReturn, firstReturn],
        },
      );

      expect(timeline.take(3).map((row) => row.title), [
        'POS Upload Created',
        'Delivery Note',
        'Packing Slips',
      ]);
      final returns = timeline.skip(3).toList();
      expect(returns.map((row) => row.title), [
        'Delivery Return',
        'Delivery Return',
      ]);
      expect(returns.map((row) => row.statusLabel), [
        'To Deliver',
        'To Deliver',
      ]);
      expect(returns.map((row) => row.timestamp), [
        firstReturn['creation'],
        secondReturn['creation'],
      ]);
      expect(returns.first.docName, 'DN-00001');
      expect(returns.last.docName, isNull);
      expect(
        returns.first.detail,
        'Driver: First Driver\nRecorded by: First Recorder\nReason: Delivery delayed',
      );
      expect(
        returns.last.detail,
        'Driver: Second Driver\nRecorded by: Second Recorder\nReason: Rejected by customer',
      );
    });

    test('retains older summaries and decodes escaped names', () {
      final history = buildPosUploadDeliveryHistory({
        'versions': [
          {'data': 'invalid Version data'},
          _returnVersion(
            commentId: 'recent',
            creation: '2026-11-25 12:30:00',
            driverName: 'Recent Driver',
            recorderName: 'Recent Recorder',
            reason: 'Late',
          ),
        ],
        'workflow_logs': [
          {
            'name': 'old-audit',
            'creation': '2026-11-20 08:30:00',
            'content':
                '<p>POS delivery · Delivery Return · Driver: A &amp; B'
                ' · recorded by O&#x27;Brien · Reason: Other · Delivery Note: DN-1</p>',
          },
          {'name': 'native-stage', 'content': 'Delivered'},
        ],
        'comments': [
          {
            'name': 'old-dispatch',
            'creation': '2026-11-20 08:00:00',
            'content': 'POS delivery · Out for Delivery · Driver: A &amp; B',
          },
        ],
      });

      expect(history.map((entry) => entry.title), [
        'Out for Delivery',
        'Delivery Return',
        'Delivery Return',
      ]);
      expect(history[1].timestamp, '2026-11-20 08:30:00');
      expect(history[1].docName, 'DN-1');
      expect(
        history[1].detail,
        "Driver: A & B\nRecorded by: O'Brien\nReason: Other reason",
      );
    });
  });

  group('buildPosUploadTimeline — DN-linked (ML/KA)', () {
    test('POS-only: node 1 reached, DN and PS nodes upcoming', () {
      final t = _dnTimeline();
      expect(t, hasLength(3));

      expect(t[0].title, 'POS Upload Created');
      expect(t[0].statusLabel, 'Pending');
      expect(t[0].state, CheckpointState.reached);
      expect(t[0].timestamp, '2026-06-30 08:00:00');
      expect(t[0].detail, '20 items');

      expect(t[1].title, 'Delivery Note');
      expect(t[1].statusLabel, 'In Progress');
      expect(t[1].state, CheckpointState.upcoming);
      expect(t[1].timestamp, isNull);

      expect(t[2].title, 'Packing Slips');
      expect(t[2].statusLabel, 'Packing');
      expect(t[2].state, CheckpointState.upcoming);
    });

    test(
      'DN present: node 2 reached with delivered/ordered qty and percent',
      () {
        final t = _dnTimeline(
          hasLinkedDoc: true,
          linkedDocName: 'ML-DN-0042',
          linkedDocCreation: '2026-06-30 09:00:00',
          orderedQty: 600,
          deliveredQty: 540,
        );

        expect(t[1].state, CheckpointState.reached);
        expect(t[1].docName, 'ML-DN-0042');
        expect(t[1].timestamp, '2026-06-30 09:00:00');
        expect(t[1].detail, '540 / 600 qty · 90%');
        expect(t[1].progress, closeTo(0.9, 1e-9));
      },
    );

    test('PS present: node 3 reached with slip count and packed items', () {
      final t = _dnTimeline(
        hasLinkedDoc: true,
        linkedDocName: 'ML-DN-0042',
        linkedDocCreation: '2026-06-30 09:00:00',
        orderedQty: 600,
        deliveredQty: 600,
        packingSlipCount: 3,
        earliestPackingSlipCreation: '2026-06-30 09:30:00',
        packedItems: 18,
        totalSerials: 20,
      );

      expect(t[2].state, CheckpointState.reached);
      expect(t[2].timestamp, '2026-06-30 09:30:00');
      expect(t[2].detail, '3 slips · 18 / 20 items packed');
    });

    test('single packing slip uses singular "slip"', () {
      final t = _dnTimeline(
        hasLinkedDoc: true,
        linkedDocName: 'ML-DN-0042',
        packingSlipCount: 1,
        earliestPackingSlipCreation: '2026-06-30 09:30:00',
        packedItems: 6,
        totalSerials: 20,
      );
      expect(t[2].detail, '1 slip · 6 / 20 items packed');
    });

    test(
      'divide-by-zero: ordered qty 0 → reached, no percent, null progress',
      () {
        final t = _dnTimeline(
          hasLinkedDoc: true,
          linkedDocName: 'ML-DN-0042',
          orderedQty: 0,
          deliveredQty: 0,
        );
        expect(t[1].state, CheckpointState.reached);
        expect(t[1].progress, isNull);
        expect(t[1].detail, isNot(contains('%')));
      },
    );

    test('percent clamps to 100 when delivered exceeds ordered', () {
      final t = _dnTimeline(
        hasLinkedDoc: true,
        linkedDocName: 'ML-DN-0042',
        orderedQty: 600,
        deliveredQty: 660,
      );
      expect(t[1].detail, contains('100%'));
      expect(t[1].progress, closeTo(1.0, 1e-9));
    });

    test('DN loading: node 2 is in the loading state', () {
      final t = _dnTimeline(isLoadingLinked: true);
      expect(t[1].state, CheckpointState.loading);
    });

    test('PS loading: node 3 is in the loading state', () {
      final t = _dnTimeline(
        hasLinkedDoc: true,
        linkedDocName: 'ML-DN-0042',
        isLoadingPackingSlips: true,
      );
      expect(t[2].state, CheckpointState.loading);
    });
  });

  group('buildPosUploadTimeline — Stock-Entry-linked (MX/KX)', () {
    List<TimelineCheckpoint> seTimeline({
      bool isLoadingLinked = false,
      bool hasLinkedDoc = false,
      String linkedDocName = '',
      String linkedDocCreation = '',
    }) => buildPosUploadTimeline(
      isStockEntryUpload: true,
      posUploadCreation: '2026-06-30 08:00:00',
      itemCount: 12,
      isLoadingLinked: isLoadingLinked,
      hasLinkedDoc: hasLinkedDoc,
      linkedDocName: linkedDocName,
      linkedDocCreation: linkedDocCreation,
      isLoadingPackingSlips: false,
      packingSlipCount: 0,
      earliestPackingSlipCreation: null,
      packedItems: 0,
      totalSerials: 0,
    );

    test('two nodes only, no packing-slip checkpoint', () {
      final t = seTimeline();
      expect(t, hasLength(2));
      expect(t[0].title, 'POS Upload Created');
      expect(t[1].title, 'Stock Entry');
    });

    test('Stock Entry present: node 2 reached with name and time', () {
      final t = seTimeline(
        hasLinkedDoc: true,
        linkedDocName: 'MX-SE-0007',
        linkedDocCreation: '2026-06-30 09:00:00',
      );
      expect(t[1].state, CheckpointState.reached);
      expect(t[1].docName, 'MX-SE-0007');
      expect(t[1].timestamp, '2026-06-30 09:00:00');
    });

    test('Stock Entry not yet linked: node 2 upcoming', () {
      final t = seTimeline();
      expect(t[1].state, CheckpointState.upcoming);
    });

    test('Stock Entry loading: node 2 loading', () {
      final t = seTimeline(isLoadingLinked: true);
      expect(t[1].state, CheckpointState.loading);
    });
  });
}
