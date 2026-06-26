import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/constants/app_theme.dart';
import 'package:multimax/app/modules/global_widgets/status_pill.dart';

(Color, Color) _expected(Color base500, Color text700, Color text300, Brightness b) {
  final fg = AppScheme.of(b).fg;
  final bg = Color.alphaBlend(base500.withValues(alpha: 0.13), fg);
  return (bg, b == Brightness.dark ? text300 : text700);
}

void main() {
  group('StatusPill.colourForStatus — ERPNext v15 ramp (light)', () {
    test('Red statuses', () {
      expect(StatusPill.colourForStatus('Open'),
          _expected(AppColors.red500, AppColors.red700, AppColors.red300, Brightness.light));
    });
    test('Blue statuses', () {
      expect(StatusPill.colourForStatus('Submitted'),
          _expected(AppColors.blue500, AppColors.blue700, AppColors.blue300, Brightness.light));
    });
    test('Orange statuses', () {
      expect(StatusPill.colourForStatus('On Hold'),
          _expected(AppColors.orange500, AppColors.orange700, AppColors.orange300, Brightness.light));
    });
    test('Yellow statuses', () {
      expect(StatusPill.colourForStatus('In Transit'),
          _expected(AppColors.yellow500, AppColors.yellow700, AppColors.yellow300, Brightness.light));
    });
    test('Green statuses', () {
      expect(StatusPill.colourForStatus('Completed'),
          _expected(AppColors.green500, AppColors.green700, AppColors.green300, Brightness.light));
    });
    test('Gray default for unknown', () {
      expect(StatusPill.colourForStatus('Wibble'),
          _expected(AppColors.gray500, AppColors.gray700, AppColors.gray300, Brightness.light));
    });
  });

  group('dark mode swaps text to the 300 ramp', () {
    test('Open in dark uses red300 text on dark-fg blend', () {
      expect(StatusPill.colourForStatus('Open', brightness: Brightness.dark),
          _expected(AppColors.red500, AppColors.red700, AppColors.red300, Brightness.dark));
    });
  });

  group('status group assignments preserved', () {
    test('Open=red, Submitted=blue, Closed=green, In Progress=gray', () {
      expect(StatusPill.colourForStatus('Open').$2, AppColors.red700);
      expect(StatusPill.colourForStatus('Submitted').$2, AppColors.blue700);
      expect(StatusPill.colourForStatus('Closed').$2, AppColors.green700);
      expect(StatusPill.colourForStatus('In Progress').$2, AppColors.gray700);
    });
  });

  group('every status routes to the correct hue (light text = <hue>700)', () {
    final groups = <Color, List<String>>{
      AppColors.red700: [
        'Draft', 'Cancelled', 'Canceled', 'Open', 'Stopped', 'Rejected', 'Expired', 'Overdue',
      ],
      AppColors.blue700: [
        'Submitted', 'Enabled', 'Stock Reserved', 'Material Transferred',
      ],
      AppColors.orange700: [
        'Not Saved', 'Not Started', 'To Bill', 'On Hold', 'Hold', 'In Process',
        'Work In Progress', 'Pending', 'To Receive and Bill', 'To Receive',
        'Stock Partially Reserved', 'Material Returned from WIP',
      ],
      AppColors.yellow700: [
        'Partially Billed', 'Partly Billed', 'In Transit', 'Partially Ordered', 'Partially Received',
      ],
      AppColors.green700: [
        'Completed', 'Active', 'Paid', 'Settled', 'Closed', 'Ordered',
        'Transferred', 'Issued', 'Received', 'Goods Transferred',
      ],
      AppColors.gray700: [
        'In Progress', 'Disabled', 'Passive', 'Return', 'Return Issued',
        'Goods In Transit', 'To Pay',
      ],
    };
    groups.forEach((expectedText, statuses) {
      for (final status in statuses) {
        test('"$status" -> correct hue', () {
          expect(StatusPill.colourForStatus(status).$2, expectedText);
        });
      }
    });
  });
}
