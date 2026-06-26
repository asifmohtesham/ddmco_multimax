import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/user_area/user_area_controller.dart';

void main() {
  test('labelForMode maps ThemeMode to a display string', () {
    expect(UserAreaController.labelForMode(ThemeMode.light), 'Light');
    expect(UserAreaController.labelForMode(ThemeMode.dark), 'Dark');
    expect(UserAreaController.labelForMode(ThemeMode.system), 'System');
  });
}
