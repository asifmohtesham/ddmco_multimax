import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/doctype_image_upload.dart';

class _UnusedApi implements ApiProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingApi extends _UnusedApi {
  final document = Completer<Response>();

  @override
  Future<Response> getDocument(String doctype, String name) => document.future;
}

void main() {
  Widget buildHarness({String? imageUrl}) => MaterialApp(
        home: Scaffold(
          body: DocTypeImageUpload(
            doctype: 'Item',
            docname: 'ITEM-001',
            fieldname: 'image',
            baseUrl: 'https://erp.example.com',
            imageUrl: imageUrl,
            onUploaded: () {},
          ),
        ),
      );

  group('DocTypeImageUpload', () {
    testWidgets('T-1: Edit badge visible when imageUrl is null', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: null));
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('T-2: Edit badge visible when imageUrl is set', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: '/files/item.jpg'));
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('T-3: tapping Edit badge opens source picker sheet with both sources', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: null));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Choose from Gallery'), findsOneWidget);
    });

    testWidgets('T-4: Remove Image row absent from sheet when imageUrl is null', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: null));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Image'), findsNothing);
    });

    testWidgets('T-5: Remove Image row present in sheet when imageUrl is set', (tester) async {
      await tester.pumpWidget(buildHarness(imageUrl: '/files/item.jpg'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Image'), findsOneWidget);
    });
  });

  Future<void> openSharedUpload(
    WidgetTester tester, {
    required ApiProvider api,
    Future<XFile?> Function(ImageSource)? pickImage,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSharedItemImageUploadSheet(
                context,
                api: api,
                itemCode: 'ITEM-001',
                photoPath: 'shared-photo.jpg',
                pickImage: pickImage,
              ),
              child: const Text('Open upload'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open upload'));
    await tester.pumpAndSettle();
  }

  testWidgets('shared upload previews the source and can pick a replacement', (
    tester,
  ) async {
    ImageSource? pickedSource;
    await openSharedUpload(
      tester,
      api: _UnusedApi(),
      pickImage: (source) async {
        pickedSource = source;
        return XFile('replacement.jpg');
      },
    );

    String previewPath() {
      final image = tester.widget<Image>(find.byType(Image));
      final provider = (image.image as ResizeImage).imageProvider as FileImage;
      return provider.file.path;
    }

    expect(find.text('ITEM-001'), findsOneWidget);
    expect(previewPath(), 'shared-photo.jpg');

    await tester.tap(find.text('Pick Another'));
    await tester.pumpAndSettle();
    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    expect(find.text('Remove Image'), findsNothing);
    await tester.tap(find.text('Choose from Gallery'));
    await tester.pumpAndSettle();
    expect(pickedSource, ImageSource.gallery);
    expect(previewPath(), 'replacement.jpg');
    expect(find.text('Upload'), findsOneWidget);
  });

  testWidgets('shared upload shows progress, then a sanitized failure', (
    tester,
  ) async {
    final api = _PendingApi();
    await openSharedUpload(tester, api: api);

    await tester.tap(find.text('Upload'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final cancel = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Cancel'),
    );
    expect(cancel.onPressed, isNull);

    final request = RequestOptions();
    api.document.completeError(
      DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 403),
        message: 'private permission details',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('You do not have permission to update this Item image.'),
      findsOneWidget,
    );
    expect(find.textContaining('private permission details'), findsNothing);
  });
}
