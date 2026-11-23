import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/common/controllers/awesome_bar_controller.dart';

Response<Map<String, dynamic>> searchReply([String? name]) => Response(
  requestOptions: RequestOptions(),
  data: {
    'message': [
      if (name != null) {'doctype': 'Delivery Note', 'name': name},
    ],
  },
);

void main() {
  test('clearing a query discards its in-flight reply', () async {
    final started = Completer<void>();
    final reply = Completer<Response>();
    final controller = AwesomeBarController(
      globalSearch: (_) {
        started.complete();
        return reply.future;
      },
    );
    addTearDown(controller.onClose);

    controller.onSearchQueryChanged('DN-001');
    await started.future;
    expect(controller.isLoading.value, isTrue);

    controller.onSearchQueryChanged(' ');
    expect(controller.options, isEmpty);
    expect(controller.isLoading.value, isFalse);

    reply.complete(searchReply('DN-001'));
    await reply.future;
    expect(controller.options, isEmpty);
    expect(controller.isLoading.value, isFalse);
  });

  test('an older reply cannot publish results or stop newer loading', () async {
    final oldStarted = Completer<void>();
    final oldReply = Completer<Response>();
    final newStarted = Completer<void>();
    final newReply = Completer<Response>();
    final controller = AwesomeBarController(
      globalSearch: (query) {
        if (query == 'DN-001') {
          oldStarted.complete();
          return oldReply.future;
        }
        expect(query, 'DN-002');
        newStarted.complete();
        return newReply.future;
      },
    );
    addTearDown(controller.onClose);

    controller.onSearchQueryChanged('DN-001');
    await oldStarted.future;
    controller.onSearchQueryChanged('DN-002');
    oldReply.complete(searchReply('DN-001'));
    await oldReply.future;
    expect(controller.options, isEmpty);
    expect(controller.isLoading.value, isTrue);

    await newStarted.future;
    newReply.complete(searchReply('DN-002'));
    await newReply.future;
    expect(controller.options.map((option) => option.value), ['DN-002']);
    expect(controller.isLoading.value, isFalse);

    controller.onSearchQueryChanged('Stock Entry');
    expect(controller.options, isEmpty);
    expect(controller.isLoading.value, isTrue);
  });

  for (final (query, value) in [
    ('Stock Entry', 'Stock Entry List'),
    ('New Item', 'New Item'),
  ]) {
    test(
      '$value restores the fresh option icon and colour from JSON',
      () async {
        final started = Completer<void>();
        final reply = Completer<Response>();
        final controller = AwesomeBarController(
          globalSearch: (_) {
            started.complete();
            return reply.future;
          },
        );
        addTearDown(controller.onClose);
        controller.onSearchQueryChanged(query);
        await started.future;
        reply.complete(searchReply());
        await reply.future;

        final fresh = controller.options.singleWhere(
          (opt) => opt.value == value,
        );
        final json = fresh.toJson();
        expect(json, isNot(contains('icon')));
        expect(json, isNot(contains('color')));
        final restored = AwesomeBarOption.fromJson(
          jsonDecode(jsonEncode(json)),
        );
        expect(fresh.icon, isNotNull);
        expect(fresh.color, isNotNull);
        expect(restored.icon, fresh.icon);
        expect(restored.color, fresh.color);
      },
    );
  }
}
