import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

void main() {
  group('StatusPill.colourForStatus — Frappe v15 indicator-pill tokens', () {
    // Red: --bg-red (red-100) / --text-on-red (red-700)
    const redBg   = Color(0xFFFFF0F0);
    const redText = Color(0xFFB52A2A);
    // Blue: --bg-blue (blue-100) / --text-on-blue (blue-700)
    const blueBg   = Color(0xFFEDF6FD);
    const blueText = Color(0xFF0070CC);
    // Orange: --bg-orange (orange-100) / --text-on-orange (orange-700)
    const orangeBg   = Color(0xFFFFF1E7);
    const orangeText = Color(0xFFBD3E0C);
    // Yellow: --bg-yellow (yellow-100) / --text-on-yellow (yellow-700)
    const yellowBg   = Color(0xFFFFF7D3);
    const yellowText = Color(0xFFAB6E05);
    // Green: --bg-green (green-100) / --text-on-green (green-800)
    const greenBg   = Color(0xFFE4F5E9);
    const greenText = Color(0xFF16794C);
    // Gray (default): --bg-gray (gray-100) / --text-on-gray (gray-700)
    const grayBg   = Color(0xFFF3F3F3);
    const grayText = Color(0xFF525252);

    void expectColour(String status, Color bg, Color text) {
      final colours = StatusPill.colourForStatus(status);
      expect(colours.$1, bg,   reason: 'bg for "$status"');
      expect(colours.$2, text, reason: 'text for "$status"');
    }

    test('Red statuses', () {
      for (final s in ['Draft', 'Cancelled', 'Canceled', 'Open',
                       'Stopped', 'Rejected', 'Expired', 'Overdue']) {
        expectColour(s, redBg, redText);
      }
    });

    test('Blue statuses', () {
      for (final s in ['Submitted', 'Enabled', 'Stock Reserved',
                       'Material Transferred']) {
        expectColour(s, blueBg, blueText);
      }
    });

    test('Orange statuses', () {
      for (final s in ['Not Saved', 'Not Started', 'To Bill', 'On Hold', 'Hold',
                       'In Process', 'Work In Progress', 'Pending',
                       'To Receive and Bill', 'To Receive',
                       'Stock Partially Reserved', 'Material Returned from WIP']) {
        expectColour(s, orangeBg, orangeText);
      }
    });

    test('Yellow statuses', () {
      for (final s in ['Partially Billed', 'Partly Billed', 'In Transit',
                       'Partially Ordered', 'Partially Received']) {
        expectColour(s, yellowBg, yellowText);
      }
    });

    test('Green statuses', () {
      for (final s in ['Completed', 'Active', 'Paid', 'Settled',
                       'Closed', 'Ordered', 'Transferred', 'Issued',
                       'Received', 'Goods Transferred']) {
        expectColour(s, greenBg, greenText);
      }
    });

    test('Gray statuses (explicit)', () {
      for (final s in ['In Progress', 'Disabled', 'Passive', 'Return',
                       'Return Issued', 'Goods In Transit', 'To Pay']) {
        expectColour(s, grayBg, grayText);
      }
    });

    test('Unknown status defaults to gray', () {
      expectColour('SomeUnknownStatus', grayBg, grayText);
    });

    // Regression: the 4 previously-wrong colour assignments
    test('Submitted is BLUE (was green)', () => expectColour('Submitted', blueBg, blueText));
    test('Open is RED (was blue)',        () => expectColour('Open',      redBg,  redText));
    test('Closed is GREEN (was gray)',    () => expectColour('Closed',    greenBg, greenText));
    test('In Progress is GRAY (was blue)', () => expectColour('In Progress', grayBg, grayText));
  });
}
