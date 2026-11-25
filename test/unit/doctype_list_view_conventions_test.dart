import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the list guide explains how caller-supplied captions wrap', () {
    final guide = File(
      'docs/doctype_list_view_conventions.md',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

    expect(
      guide,
      contains(
        'Applied chips display the caption supplied by the caller. '
        'By default, long captions wrap within their target.',
      ),
    );
  });
}
