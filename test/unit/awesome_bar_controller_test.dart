import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/common/controllers/awesome_bar_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    // The previous results stay visible while the next search loads.
    controller.onSearchQueryChanged('Stock Entry');
    expect(controller.options.map((option) => option.value), ['DN-002']);
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

  group('submitting a search', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<List<String>> savedQueries() async => [
      for (final option in await AwesomeBarRecentStore.read())
        if (option.isQuery) option.value,
    ];

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 350));

    test(
      'saves a search that found nothing, even if submitted early',
      () async {
        final reply = Completer<Response>();
        final controller = AwesomeBarController(
          globalSearch: (_) => reply.future,
        );
        addTearDown(controller.onClose);

        controller.onSearchQueryChanged('zzqx');
        controller.onQuerySubmitted(' zzqx ');
        await settle();
        expect(await savedQueries(), isEmpty);
        reply.complete(searchReply());
        await settle();
        expect(await savedQueries(), ['zzqx']);
      },
    );

    test(
      'does not save a search with results or one never submitted',
      () async {
        final controller = AwesomeBarController(
          globalSearch: (query) async =>
              searchReply(query == 'DN' ? 'DN-0001' : null),
        );
        addTearDown(controller.onClose);

        controller.onSearchQueryChanged('DN');
        await settle();
        controller.onQuerySubmitted('DN');
        controller.onSearchQueryChanged('typed only');
        await settle();
        await settle();
        expect(await savedQueries(), isEmpty);
      },
    );

    test('does not save when the search request fails', () async {
      final controller = AwesomeBarController(
        globalSearch: (_) async => throw Exception('offline'),
      );
      addTearDown(controller.onClose);

      controller.onSearchQueryChanged('zzqx');
      await settle();
      controller.onQuerySubmitted('zzqx');
      await settle();
      expect(await savedQueries(), isEmpty);
    });

    test(
      'a submit for an older query is dropped when the text changes',
      () async {
        final controller = AwesomeBarController(
          globalSearch: (_) async => searchReply(),
        );
        addTearDown(controller.onClose);

        controller.onSearchQueryChanged('first');
        controller.onQuerySubmitted('first');
        controller.onSearchQueryChanged('second');
        await settle();
        await settle();
        expect(await savedQueries(), isEmpty);
      },
    );
  });
}
