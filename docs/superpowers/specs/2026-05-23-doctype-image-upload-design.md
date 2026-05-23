# DocType Image Upload — Design Spec

**Date:** 2026-05-23  
**Feature:** Upload / remove the `image` field on any Frappe DocType from the Flutter app  
**First target:** Item form (Nav Drawer → Item → Overview tab)

---

## Overview

The Item form's Overview tab currently displays the item image read-only. This feature adds a camera/gallery upload trigger so users can set or replace a DocType's image field directly from the device, matching how Frappe ERPNext handles image fields on the desktop.

The implementation is a **generic reusable widget** (`DocTypeImageUpload`) usable on any DocType form that has an `Attach Image` field — not Item-specific.

---

## Architecture

### New files

| File | Purpose |
|---|---|
| `lib/app/modules/global_widgets/doctype_image_upload.dart` | Reusable upload widget |

### Modified files

| File | Change |
|---|---|
| `pubspec.yaml` | Add `image_picker` dependency |
| `lib/app/data/providers/api_provider.dart` | Add `uploadFile()` method |
| `lib/app/modules/item/form/item_form_screen.dart` | Replace existing image block with `DocTypeImageUpload` |
| `lib/app/modules/item/form/item_form_controller.dart` | No new logic; `fetchItemDetails()` serves as the refresh callback |

---

## Component: `DocTypeImageUpload`

### Widget signature

```dart
class DocTypeImageUpload extends StatefulWidget {
  final String doctype;         // e.g. "Item"
  final String docname;         // e.g. "ITEM-001"
  final String fieldname;       // e.g. "image"
  final String baseUrl;         // ApiProvider.baseUrl — for constructing full URLs
  final String? imageUrl;       // current relative path from Frappe, null = no image
  final VoidCallback onUploaded; // called after successful upload or removal
}
```

### Internal state

| State | Type | Purpose |
|---|---|---|
| `_isUploading` | `bool` | Shows progress overlay during upload/removal |

### Layout

- **Container:** 200 px tall, full width, `BorderRadius.circular(12)`, matches the existing image container in `ItemFormScreen`
- **Image present:** renders `Image.network('$baseUrl$imageUrl')` with `BoxFit.contain`, same loading/error builders as existing code; tap opens full-screen viewer (re-uses existing `_openFullScreenImage` logic, extracted or duplicated)
- **No image:** renders the existing placeholder (`Icons.image_not_supported_outlined` on `surfaceContainerHighest` background)
- **Edit badge:** `Positioned` bottom-right corner — a pill (`BorderRadius.circular(20)`) with `Icons.camera_alt` + "Edit" label, `rgba(0,0,0,0.65)` background, always visible

### Interaction flow

1. User taps the Edit badge
2. `showModalBottomSheet` opens with three rows:
   - **Take Photo** (`Icons.camera_alt_outlined`) — calls `ImagePicker().pickImage(source: ImageSource.camera)`
   - **Choose from Gallery** (`Icons.photo_library_outlined`) — calls `ImagePicker().pickImage(source: ImageSource.gallery)`
   - **Remove Image** (`Icons.delete_outline`, destructive red) — shown only when `imageUrl != null`
3. On image pick: dismiss sheet, set `_isUploading = true`, render spinner overlay on the image area
4. Call `ApiProvider.uploadFile(...)` — multipart POST to Frappe
5. On success: call `onUploaded()`, set `_isUploading = false`
6. On remove: call `ApiProvider.updateDocument(doctype, docname, {'image': null})`, then `onUploaded()`, set `_isUploading = false`
7. On error: set `_isUploading = false`, show `GlobalSnackbar.error(...)`

### Upload progress overlay

While `_isUploading` is true, render a semi-transparent overlay (`Colors.black54`) over the image container with a centred `CircularProgressIndicator(color: cs.primary)`.

---

## API: `ApiProvider.uploadFile()`

```dart
Future<String> uploadFile({
  required String filePath,
  required String doctype,
  required String docname,
  required String fieldname,
  bool isPrivate = false,
}) async
```

**Endpoint:** `POST /api/method/upload_file`  
**Content-type:** `multipart/form-data`

**Form fields:**

| Field | Value |
|---|---|
| `file` | `MultipartFile.fromFileSync(filePath, filename: basename(filePath))` |
| `doctype` | e.g. `"Item"` |
| `docname` | e.g. `"ITEM-001"` |
| `fieldname` | e.g. `"image"` |
| `is_private` | `"0"` or `"1"` |
| `folder` | `"Home/Attachments"` |

**Response parsing:**

```json
{
  "message": {
    "file_url": "/files/item-image.jpg"
  }
}
```

Returns `response.data['message']['file_url']` as a `String`.  
Throws `Exception` on non-200 status or missing `file_url`.

---

## Integration in `ItemFormScreen`

In `_buildOverviewTab`, replace the existing `if (item.image != null) GestureDetector(...)` image block with:

```dart
DocTypeImageUpload(
  doctype: 'Item',
  docname: item.itemCode,
  fieldname: 'image',
  imageUrl: item.image,
  baseUrl: baseUrl,
  onUploaded: controller.fetchItemDetails,
),
```

The widget renders identically to the current image container when read-only (no image to upload / view). When upload completes, `fetchItemDetails()` re-fetches from Frappe and the `Obx` rebuilds reactively.

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| Server 403 / permission denied | `GlobalSnackbar.error('You do not have permission to edit this document')` |
| Network error / timeout | `GlobalSnackbar.error('Upload failed. Check your connection.')` |
| User cancels image picker | Silent — picker returns `null`, no upload attempted |
| Remove while offline | `GlobalSnackbar.error(...)`, field unchanged |
| Image too large / server-side validation | Surfaces Frappe's error message from response body |

Permissions are enforced entirely server-side by Frappe's `upload_file` endpoint, matching ERPNext desktop behaviour. No client-side role check is added.

---

## Dependencies

- `image_picker` — standard Flutter package for camera and gallery access on Android/iOS
- No other new packages required; `dio` (already present) handles multipart upload via `FormData`

---

## Out of Scope

- Cropping or resizing images before upload (Frappe desktop does not do this)
- Progress percentage (Frappe desktop shows spinner only, not percentage)
- Multi-image upload (image field is single-valued in Frappe)
- Offline queue / retry logic
