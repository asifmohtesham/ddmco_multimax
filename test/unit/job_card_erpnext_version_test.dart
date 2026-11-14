import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/models/job_card_model.dart';
import 'package:multimax/app/data/providers/job_card_provider.dart';

void main() {
  group('JobCardProvider.timeLogParams', () {
    final payload = {
      'job_card_id': 'PO-JOB00001',
      'start_time': '2026-09-27 10:00:00',
      'employees': [
        {'employee': 'HR-EMP-00013'},
      ],
    };

    test('sends the payload under args (ERPNext v15)', () {
      final params = JobCardProvider.timeLogParams(payload);
      expect(json.decode(params['args'] as String), payload);
    });

    test('sends the payload under kwargs (ERPNext v16)', () {
      final params = JobCardProvider.timeLogParams(payload);
      expect(json.decode(params['kwargs'] as String), payload);
    });

    test('sends nothing else', () {
      expect(
        JobCardProvider.timeLogParams(payload).keys,
        unorderedEquals(['args', 'kwargs']),
      );
    });
  });

  group('JobCardProvider.pausePayload', () {
    test('pausing writes both the v15 status and the v16 flag', () {
      expect(
        JobCardProvider.pausePayload(paused: true),
        {'status': 'On Hold', 'is_paused': 1},
      );
    });

    test('releasing clears the flag and leaves status to the server', () {
      expect(JobCardProvider.pausePayload(paused: false), {'is_paused': 0});
    });
  });

  group('JobCard.isPaused', () {
    test('is null when the server has no is_paused field (v15)', () {
      final jc = JobCard.fromJson({'name': 'PO-JOB00001', 'status': 'On Hold'});
      expect(jc.isPaused, isNull);
      expect(jc.isOnHold, isTrue);
    });

    test('is true when is_paused is 1 (v16)', () {
      final jc = JobCard.fromJson(
          {'name': 'PO-JOB00001', 'status': 'On Hold', 'is_paused': 1});
      expect(jc.isPaused, isTrue);
    });

    test('is false when is_paused is 0 (v16)', () {
      final jc = JobCard.fromJson({
        'name': 'PO-JOB00001',
        'status': 'Work In Progress',
        'is_paused': 0,
      });
      expect(jc.isPaused, isFalse);
    });

    test('is false when is_paused is present but null', () {
      final jc = JobCard.fromJson({'name': 'PO-JOB00001', 'is_paused': null});
      expect(jc.isPaused, isFalse);
    });
  });
}
