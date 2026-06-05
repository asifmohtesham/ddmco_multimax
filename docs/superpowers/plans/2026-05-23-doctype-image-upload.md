# DocType Image Upload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable `DocTypeImageUpload` widget that lets users upload, replace, or remove a Frappe DocType image field from the Flutter app, wired into the Item form as the first consumer.

**Architecture:** A self-contained `StatefulWidget` in `global_widgets/` manages all transient upload state. It lazily resolves `ApiProvider` via `Get.find()` only when an upload is triggered. `ApiProvider` gains one new `uploadFile()` multipart method and a testable static parser. `ItemFormScreen` replaces its existing read-only image block with the widget in a single-line swap.

**Tech Stack:** Flutter/Dart, GetX, Dio (multipart FormData), `image_picker` package, Frappe `/api/method/upload_file` endpoint.

---

## File Map

| Action | File |
|---|---|
| Modify | `pubspec.yaml` |
| Modify | `lib/app/data/providers/api_provider.dart` |
| Create | `lib/app/modules/global_widgets/doctype_image_upload.dart` |
| Modify | `lib/app/modules/item/form/item_form_screen.dart` |
| Create | `test/unit/upload_file_response_test.dart` |
| Create | `test/widget/doctype_image_upload_test.dart` |

---

## Task 1: Add `image_picker` dependency

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, add `image_picker` under `dependencies` (after `shared_preferences`):

```yaml
  shared_preferences: ^2.5.5
  image_picker: ^1.1.2
```

- [ ] **Step 2: Install**

```
flutter pub get
```

Expected: resolves without conflicts. `image_picker` is a standard Flutter team package.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add image_picker for camera and gallery access"
```

---

## Task 2: Add `ApiProvider.uploadFile()` and its response parser

**Files:**
- Modify: `lib/app/data/providers/api_provider.dart`
- Create: `test/unit/upload_file_response_test.dart`

- [ ] **Step 1: Write the failing unit test**

Create `test/unit/upload_file_response_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/data/providers/api_provider.dart';

void main() {
  group('ApiProvider.parseUploadFileResponse', () {
    test('T-1: returns null when data is null', () {
      expect(ApiProvider.parseUploadFileResponse(null), isNull);
    });

    test('T-2: returns null when message key is absent', () {
      expect(ApiProvider.parseUploadFileResponse({'other': 'data'}), isNull);
    });

    test('T-3: returns null when file_url key is absent from message', () {
      final data = <String, dynamic>{'message': {'name': 'File Name'}};
      expect(ApiProvider.parseUploadFileResponse(data), isNull);
    });

    test('T-4: returns file_url from a well-formed response', () {
      final data = <String, dynamic>{
        'message': {
          'file_url': '/files/item-image.jpg',
          'file_name': 'item-image.jpg',
        },
      };
      expect(ApiProvider.parseUploadFileResponse(data), '/files/item-image.jpg');
    });

    test('T-5: returns null when file_url value is not a String', () {
      final data = <String, dynamic>{'message': {'file_url': 42}};
      expect(ApiProvider.parseUploadFileResponse(data), isNull);
    });
  });
}
```

- [ ] **Step 2: Run test — verify it fails**

```
flutter test test/unit/upload_file_response_test.dart --no-pub
```

Expected: compile error — `parseUploadFileResponse` does not exist yet.

- [ ] **Step 3: Add `package:path/path.dart` import and `parseUploadFileResponse` + `uploadFile()` to `ApiProvider`**

In `lib/app/data/providers/api_provider.dart`, add `package:path/path.dart` to the imports block (after the existing `dart:convert` import):

```dart
import 'package:path/path.dart' as p;
```

Then, immediately after the existing `parseItemVariantDetailsResponse` static method (around line 517), add:

```dart
  /// Exposed as a public static method so unit tests can exercise the parsing
  /// logic without a live HTTP connection.
  static String? parseUploadFileResponse(Map<String, dynamic>? data) {
    if (data == null) return null;
    return data['message']?['file_url'] as String?;
  }

  // ---------------------------------------------------------------------------
  // FILE UPLOAD
  // ---------------------------------------------------------------------------

  /// Uploads [filePath] to Frappe and links it to [fieldname] on
  /// [doctype]/[docname].
  ///
  /// Returns the relative file_url (e.g. "/files/image.jpg") on success.
  /// Throws [DioException] on HTTP error; throws [Exception] when the server
  /// response does not contain a file_url (malformed response).
  Future<String> uploadFile({
    required String filePath,
    required String doctype,
    required String docname,
    required String fieldname,
    bool isPrivate = false,
  }) async {
    if (!_dioInitialised) await _initDio();
    final formData = FormData.fromMap({
      'file'      : await MultipartFile.fromFile(filePath, filename: p.basename(filePath)),
      'doctype'   : doctype,
      'docname'   : docname,
      'fieldname' : fieldname,
      'is_private': isPrivate ? '1' : '0',
      'folder'    : 'Home/Attachments',
    });
    final response = await _dio.post('/api/method/upload_file', data: formData);
    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        message: 'Upload failed with status ${response.statusCode}',
      );
    }
    final fileUrl = parseUploadFileResponse(
      response.data as Map<String, dynamic>?,
    );
    if (fileUrl == null || fileUrl.isEmpty) {
      throw Exception('Server returned no file_url');
    }
    return fileUrl;
  }
```

- [ ] **Step 4: Run test — verify it passes**

```
flutter test test/unit/upload_file_response_test.dart --no-pub
```

Expected: all 5 tests PASS.

- [ ] **Step 5: Run analyzer**

```
flutter analyze lib/app/data/providers/api_provider.dart
```

Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/app/data/providers/api_provider.dart test/unit/upload_file_response_test.dart
git commit -m "feat(api): add uploadFile() multipart method and parseUploadFileResponse parser"
```

---

## Task 3: Create `DocTypeImageUpload` widget

**Files:**
- Create: `lib/app/modules/global_widgets/doctype_image_upload.dart`
- Create: `test/widget/doctype_image_upload_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Create `test/widget/doctype_image_upload_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multimax/app/modules/global_widgets/doctype_image_upload.dart';

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
}
```

- [ ] **Step 2: Run test — verify it fails**

```
flutter test test/widget/doctype_image_upload_test.dart --no-pub
```

Expected: compile error — `DocTypeImageUpload` does not exist yet.

- [ ] **Step 3: Create the widget**

Create `lib/app/modules/global_widgets/doctype_image_upload.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:image_picker/image_picker.dart';
import 'package:multimax/app/data/providers/api_provider.dart';
import 'package:multimax/app/modules/global_widgets/global_snackbar.dart';

/// Reusable image-field widget for any Frappe DocType.
///
/// Shows the current image (tap to full-screen) with an always-visible Edit
/// badge. Tapping the badge opens a camera / gallery / remove picker.
/// Permissions are enforced server-side by Frappe's upload_file endpoint,
/// mirroring ERPNext desktop behaviour exactly.
class DocTypeImageUpload extends StatefulWidget {
  final String doctype;
  final String docname;
  final String fieldname;
  final String baseUrl;
  final String? imageUrl;

  /// Called after a successful upload OR removal so the parent can refresh
  /// its document data. Use `() { controller.fetchDocument(); }` at call sites
  /// to discard the returned Future and satisfy VoidCallback's type.
  final VoidCallback onUploaded;

  const DocTypeImageUpload({
    super.key,
    required this.doctype,
    required this.docname,
    required this.fieldname,
    required this.baseUrl,
    required this.imageUrl,
    required this.onUploaded,
  });

  @override
  State<DocTypeImageUpload> createState() => _DocTypeImageUploadState();
}

class _DocTypeImageUploadState extends State<DocTypeImageUpload> {
  bool _isUploading = false;
  final _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 200,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Image or placeholder ────────────────────────────────────────
          if (widget.imageUrl != null)
            GestureDetector(
              onTap: () => _openFullScreen(context, '${widget.baseUrl}${widget.imageUrl}'),
              child: Image.network(
                '${widget.baseUrl}${widget.imageUrl}',
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                          : null,
                      color: cs.primary,
                      strokeWidth: 2,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 50,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 50,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),

          // ── Upload progress overlay ─────────────────────────────────────
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(color: cs.primary, strokeWidth: 2),
              ),
            ),

          // ── Edit badge ──────────────────────────────────────────────────
          if (!_isUploading)
            Positioned(
              bottom: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _showSourcePicker(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.camera_alt, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showSourcePicker(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              subtitle: const Text('Open camera'),
              onTap: () {
                Get.back();
                _pickAndUpload(ImageSource.camera);
              },
            ),
            Divider(height: 1, color: cs.outlineVariant),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Pick from device'),
              onTap: () {
                Get.back();
                _pickAndUpload(ImageSource.gallery);
              },
            ),
            if (widget.imageUrl != null) ...[
              Divider(height: 1, color: cs.outlineVariant),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('Remove Image', style: TextStyle(color: cs.error)),
                subtitle: const Text('Clears the image field'),
                onTap: () {
                  Get.back();
                  _removeImage();
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final file = await _picker.pickImage(source: source);
    if (file == null || !mounted) return;
    setState(() => _isUploading = true);
    try {
      await Get.find<ApiProvider>().uploadFile(
        filePath: file.path,
        doctype: widget.doctype,
        docname: widget.docname,
        fieldname: widget.fieldname,
      );
      widget.onUploaded();
    } catch (e) {
      GlobalSnackbar.error(message: _errorMessage(e));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _removeImage() async {
    if (!mounted) return;
    setState(() => _isUploading = true);
    try {
      await Get.find<ApiProvider>().updateDocument(
        widget.doctype,
        widget.docname,
        {'image': null},
      );
      widget.onUploaded();
    } catch (e) {
      GlobalSnackbar.error(message: _errorMessage(e));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _errorMessage(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 403) {
        return 'You do not have permission to edit this document';
      }
      return 'Upload failed. Check your connection.';
    }
    return 'An unexpected error occurred.';
  }

  void _openFullScreen(BuildContext context, String url) {
    Get.dialog(
      barrierDismissible: true,
      barrierColor: Colors.black87,
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
              Get.back();
            }
          },
          child: Stack(
            children: [
              InteractiveViewer(
                child: Center(
                  child: Image.network(
                    url,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: Get.back,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests — verify they pass**

```
flutter test test/widget/doctype_image_upload_test.dart --no-pub
```

Expected: all 5 tests PASS.

- [ ] **Step 5: Run analyzer**

```
flutter analyze lib/app/modules/global_widgets/doctype_image_upload.dart
```

Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add lib/app/modules/global_widgets/doctype_image_upload.dart test/widget/doctype_image_upload_test.dart
git commit -m "feat(global-widgets): add DocTypeImageUpload widget for camera/gallery image upload"
```

---

## Task 4: Wire `DocTypeImageUpload` into `ItemFormScreen`

**Files:**
- Modify: `lib/app/modules/item/form/item_form_screen.dart`

- [ ] **Step 1: Add the import**

In `lib/app/modules/item/form/item_form_screen.dart`, add the import after the existing import block:

```dart
import 'package:multimax/app/modules/global_widgets/doctype_image_upload.dart';
```

- [ ] **Step 2: Replace the existing image block**

In `_buildOverviewTab`, locate and remove the entire `if (item.image != null) GestureDetector(...)` block (lines 98–138). Replace it with:

```dart
          DocTypeImageUpload(
            doctype: 'Item',
            docname: item.itemCode,
            fieldname: 'image',
            imageUrl: item.image,
            baseUrl: baseUrl,
            onUploaded: () { controller.fetchItemDetails(); },
          ),
```

The full `_buildOverviewTab` method should now start like this after the change (first ~20 lines shown for context):

```dart
  Widget _buildOverviewTab(BuildContext context, Item item, ColorScheme cs) {
    final String baseUrl = Get.find<ApiProvider>().baseUrl;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DocTypeImageUpload(
            doctype: 'Item',
            docname: item.itemCode,
            fieldname: 'image',
            imageUrl: item.image,
            baseUrl: baseUrl,
            onUploaded: () { controller.fetchItemDetails(); },
          ),

          _buildSectionCard(
            // ... rest unchanged
```

- [ ] **Step 3: Remove the now-unused `_openFullScreenImage` method from `ItemFormScreen`**

The `_openFullScreenImage` method (lines 931–979 in the original file) is still called from `_buildAttachmentsTab` (line 755). **Do NOT remove it.** Only the image block in `_buildOverviewTab` is replaced — the attachments tab still uses `_openFullScreenImage` directly.

- [ ] **Step 4: Run the analyzer**

```
flutter analyze lib/app/modules/item/form/item_form_screen.dart
```

Expected: no issues. If `_openFullScreenImage` is flagged as unused, verify the attachments tab still calls it; it should not be flagged.

- [ ] **Step 5: Run all tests**

```
flutter test --no-pub
```

Expected: all tests pass. No regressions.

- [ ] **Step 6: Manual smoke test on device**

```
flutter run -d <device_id>
```

Test the following:
1. Nav Drawer → Item → tap any item → Overview tab: image container always visible (with content or placeholder)
2. Tap the Edit badge → bottom sheet appears with "Take Photo", "Choose from Gallery"
3. Item without image: "Remove Image" absent from sheet
4. Item with image: "Remove Image" present in sheet; tapping it clears the image and refreshes
5. Gallery pick → image uploads → form refreshes with new image
6. Camera pick → photo taken → image uploads → form refreshes
7. Cancel image picker (back button) → no upload, no error
8. Attachments tab: full-screen viewer still works (regression check)

- [ ] **Step 7: Commit**

```bash
git add lib/app/modules/item/form/item_form_screen.dart
git commit -m "feat(item-form): replace read-only image block with DocTypeImageUpload widget"
```
