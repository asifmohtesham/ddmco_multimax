import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

void main() {
  group('StatusPill.colourForStatus — ERPNext v16 verbatim', () {
    // Red: surface-red-2 / ink-red-4
    const redBg   = Color(0xFFFFE7E7);
    const redText = Color(0xFFCC2929);
    // Blue: surface-blue-2 / ink-blue-2
    const blueBg   = Color(0xFFE6F4FF);
    const blueText = Color(0xFF0289F7);
    // Orange (amber): surface-amber-1 / ink-amber-3
    const amberBg   = Color(0xFFFDFAED);
    const amberText = Color(0xFFDB7706);
    // Yellow: yellow/100 / yellow/700
    const yellowBg   = Color(0xFFFFF7D3);
    const yellowText = Color(0xFFAB6E05);
    // Green: surface-green-2 / ink-green-3
    const greenBg   = Color(0xFFE4FAEB);
    const greenText = Color(0xFF278F5E);
    // Gray (default): surface-gray-2 / ink-gray-6
    const grayBg   = Color(0xFFF3F3F3);
    const grayText = Color(0xFF525252);

    void expectColour(String status, Color bg, Color text) {
      final colours = StatusPill.colourForStatus(status);
      expect(colours.$1, bg,   reason: 'bg for "$status"');
      expect(colours.$2, text, reason: 'text for "$status"');
    }

    test('Red statuses', () {
      for (final s in ['Draft', 'Cancelled', 'Open', 'Not Started',
                       'Stopped', 'Rejected', 'Expired', 'Overdue']) {
        expectColour(s, redBg, redText);
      }
    });

    test('Blue statuses', () {
      for (final s in ['Submitted', 'Stock Reserved']) {
        expectColour(s, blueBg, blueText);
      }
    });

    test('Amber statuses', () {
      for (final s in ['To Bill', 'On Hold', 'Hold', 'In Process', 'Pending',
                       'Not Saved', 'To Receive and Bill', 'To Receive',
                       'Stock Partially Reserved', 'Material Returned from WIP']) {
        expectColour(s, amberBg, amberText);
      }
    });

    test('Yellow statuses', () {
      for (final s in ['Partially Billed', 'Partly Billed', 'In Transit',
                       'Partially Ordered', 'Partially Received']) {
        expectColour(s, yellowBg, yellowText);
      }
    });

    test('Green statuses', () {
      for (final s in ['Completed', 'Active', 'Paid', 'Settled', 'Enabled',
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
