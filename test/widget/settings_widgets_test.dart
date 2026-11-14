import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/settings_group.dart';
import 'package:multimax/app/modules/global_widgets/settings_row.dart';
import 'package:multimax/app/modules/global_widgets/settings_controls.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('SettingsGroup shows uppercased label and its child rows',
      (tester) async {
    await tester.pumpWidget(_host(const SettingsGroup(
      label: 'Preferences',
      children: [
        SettingsRow(icon: Icons.palette_outlined, title: 'Theme', value: 'Dark'),
      ],
    )));
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
  });

  testWidgets('SettingsRow fires onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(SettingsRow(
      icon: Icons.info_outline,
      title: 'System Information',
      onTap: () => tapped = true,
    )));
    await tester.tap(find.text('System Information'));
    expect(tapped, isTrue);
  });

  testWidgets('SettingsSegmented selects on tap', (tester) async {
    String picked = 'a';
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (_, setState) => SettingsSegmented<String>(
        value: picked,
        onChanged: (v) => setState(() => picked = v),
        options: const [
          SegmentOption(value: 'a', label: 'Alpha'),
          SegmentOption(value: 'b', label: 'Beta'),
        ],
      ),
    )));
    await tester.tap(find.text('Beta'));
    await tester.pump();
    expect(picked, 'b');
  });

  testWidgets('SettingsSliderRow renders value + suffix', (tester) async {
    await tester.pumpWidget(_host(SettingsSliderRow(
      label: 'Delay',
      value: 4,
      min: 1,
      max: 10,
      suffix: 's',
      onChanged: (_) {},
    )));
    expect(find.text('Delay'), findsOneWidget);
    expect(find.text('4s'), findsOneWidget);
  });
}
